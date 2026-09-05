defmodule GuildfordVue.PasswordBreach.Hibp do
  @moduledoc """
  Sprint 12 Slice 3 — real
  [Have I Been Pwned](https://haveibeenpwned.com/API/v3#PwnedPasswords)
  `PasswordBreach` adapter using the **k-anonymity** API.

  ## What leaves the server

  1. SHA-1 the plaintext password locally.
  2. Send only the first **5 hex chars** of the SHA-1 to
     `api.pwnedpasswords.com`.
  3. The response is a newline-separated list of `<suffix>:<count>`
     pairs covering every breached password whose SHA-1 starts with
     those 5 chars (~500 entries per prefix on average).
  4. Match the local suffix locally.

  The plaintext password never crosses the wire.

  ## Config

  Swap the Stub for this adapter in `config/runtime.exs`:

      config :guildford_vue, :password_breach,
        GuildfordVue.PasswordBreach.Hibp

  ## Reliability

  Network failures, slow responses, and 4xx/5xx all return
  `{:error, reason}` — the schema-side validator treats that as
  `:ok` so a HIBP outage never blocks legitimate registrations
  / password resets. Tested via `bypass` in
  `test/guildford_vue/password_breach/hibp_test.exs`.
  """

  @behaviour GuildfordVue.PasswordBreach

  @default_base_url "https://api.pwnedpasswords.com/range"
  @default_timeout_ms 2_500

  @impl true
  def check(password) when is_binary(password) do
    {prefix, suffix} = sha1_split(password)

    case fetch_suffixes(prefix) do
      {:ok, body} -> match_suffix(body, suffix)
      {:error, _} = err -> err
    end
  end

  # SHA-1, upcased, split into 5-char prefix + remaining 35 chars.
  defp sha1_split(password) do
    hex = :crypto.hash(:sha, password) |> Base.encode16(case: :upper)
    {String.slice(hex, 0..4), String.slice(hex, 5..-1//1)}
  end

  defp fetch_suffixes(prefix) do
    url = "#{base_url()}/#{prefix}"

    headers = [
      {"add-padding", "true"},
      {"user-agent", "guildford-vue-#{Application.spec(:guildford_vue, :vsn)}"}
    ]

    case req_get(url, headers) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:hibp_http, status}}

      {:error, reason} ->
        {:error, {:hibp_network, reason}}
    end
  end

  defp match_suffix(body, our_suffix) do
    # Body lines look like: "<35-char-suffix>:<count>\r" — match
    # case-insensitively because HIBP returns uppercase.
    our_suffix_up = String.upcase(our_suffix)

    body
    |> String.split("\n", trim: true)
    |> Enum.reduce_while(:ok, fn line, acc -> parse_line(line, our_suffix_up, acc) end)
  end

  defp parse_line(line, our_suffix_up, acc) do
    with [suffix, count_str] <- String.split(line, ":", parts: 2),
         true <- String.trim(suffix) == our_suffix_up,
         {n, _} when n > 0 <- Integer.parse(String.trim(count_str)) do
      {:halt, {:error, :breached, n}}
    else
      _ -> {:cont, acc}
    end
  end

  defp req_get(url, headers) do
    # `:req_options` lets tests inject their own Req instance
    # without polluting prod config.
    opts =
      Keyword.merge(
        [url: url, headers: headers, receive_timeout: @default_timeout_ms],
        Application.get_env(:guildford_vue, :hibp_req_options, [])
      )

    Req.request(opts)
  end

  defp base_url do
    Application.get_env(:guildford_vue, :hibp_base_url, @default_base_url)
  end
end
