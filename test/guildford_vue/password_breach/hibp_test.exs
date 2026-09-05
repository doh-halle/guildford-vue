defmodule GuildfordVue.PasswordBreach.HibpTest do
  @moduledoc """
  Sprint 12 Slice 3 — HIBP real adapter. Drives the k-anonymity
  query through a Bypass-stubbed HTTP server so the test never
  touches the real api.pwnedpasswords.com.
  """
  use ExUnit.Case, async: false

  alias GuildfordVue.PasswordBreach.Hibp

  setup do
    bypass = Bypass.open()
    previous_url = Application.get_env(:guildford_vue, :hibp_base_url)
    previous_opts = Application.get_env(:guildford_vue, :hibp_req_options)
    Application.put_env(:guildford_vue, :hibp_base_url, "http://localhost:#{bypass.port}/range")
    # Disable Req's retry-on-error so the network-down test isn't a
    # 14-second wait.
    Application.put_env(:guildford_vue, :hibp_req_options, retry: false)

    on_exit(fn ->
      Application.put_env(:guildford_vue, :hibp_base_url, previous_url)
      Application.put_env(:guildford_vue, :hibp_req_options, previous_opts)
    end)

    %{bypass: bypass}
  end

  defp sha1_prefix(password) do
    :crypto.hash(:sha, password) |> Base.encode16(case: :upper) |> String.slice(0..4)
  end

  defp sha1_suffix(password) do
    :crypto.hash(:sha, password) |> Base.encode16(case: :upper) |> String.slice(5..-1//1)
  end

  describe "check/1" do
    test "matches a breached password — returns {:error, :breached, count}", %{bypass: bypass} do
      pw = "password"
      prefix = sha1_prefix(pw)
      suffix = sha1_suffix(pw)

      Bypass.expect_once(bypass, "GET", "/range/#{prefix}", fn conn ->
        body =
          [
            "0000000000000000000000000000000000A:42",
            "#{suffix}:9876543",
            "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:1"
          ]
          |> Enum.join("\n")

        Plug.Conn.resp(conn, 200, body)
      end)

      assert {:error, :breached, 9_876_543} = Hibp.check(pw)
    end

    test ":ok when our suffix is absent from the prefix bucket", %{bypass: bypass} do
      Bypass.expect_once(bypass, fn conn ->
        body = "0000000000000000000000000000000000A:1\nFFFF…:2"
        Plug.Conn.resp(conn, 200, body)
      end)

      assert :ok = Hibp.check("a-fresh-unbreached-password-#{System.unique_integer()}")
    end

    test "case-insensitive suffix match", %{bypass: bypass} do
      pw = "MixedCasePassword"
      suffix = sha1_suffix(pw)

      Bypass.expect_once(bypass, fn conn ->
        # Server returns uppercase; we still match.
        body = "#{String.upcase(suffix)}:5"
        Plug.Conn.resp(conn, 200, body)
      end)

      assert {:error, :breached, 5} = Hibp.check(pw)
    end

    test "non-200 → {:error, {:hibp_http, status}}", %{bypass: bypass} do
      Bypass.expect_once(bypass, fn conn ->
        Plug.Conn.resp(conn, 503, "service unavailable")
      end)

      assert {:error, {:hibp_http, 503}} = Hibp.check("anything")
    end

    test "network unreachable → {:error, {:hibp_network, _}}", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, {:hibp_network, _}} = Hibp.check("anything")
    end

    test "k-anonymity: only the 5-char prefix is sent on the wire", %{bypass: bypass} do
      pw = "supersecret-password-please"
      prefix = sha1_prefix(pw)

      Bypass.expect_once(bypass, "GET", "/range/#{prefix}", fn conn ->
        # Assert the URL the client built only carries the prefix.
        assert conn.request_path == "/range/#{prefix}"
        refute conn.query_string =~ "password"
        Plug.Conn.resp(conn, 200, "")
      end)

      _ = Hibp.check(pw)
    end
  end
end
