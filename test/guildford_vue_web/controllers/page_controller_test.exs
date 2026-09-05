defmodule GuildfordVueWeb.PageControllerTest do
  use GuildfordVueWeb.ConnCase, async: true

  describe "GET /" do
    test "renders the Guildford Vue landing", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ "Book your UK examination slot"
      assert html =~ "Candidate sign in"
      assert html =~ "Exam centre sign in"
      assert html =~ "Back office"
    end

    test "exposes a slot-availability key with all four status pills", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ "status-badge--available"
      assert html =~ "status-badge--limited"
      assert html =~ "status-badge--fully-booked"
      assert html =~ "confirmed-pill"
    end

    test "loads Manrope and IBM Plex Mono via Google Fonts", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ "fonts.googleapis.com"
      assert html =~ "Manrope"
      assert html =~ "IBM+Plex+Mono"
    end
  end
end
