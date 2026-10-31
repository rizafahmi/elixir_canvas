defmodule ElixirCanvasWeb.CanvasLiveTest do
  use ElixirCanvasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ElixirCanvas.Document
  alias Hakushi.{Change, Graph}

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: directory} do
    path = Path.join(directory, "portable.json")

    source =
      Path.expand("../../fixtures/document.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    File.write!(path, Jason.encode!(source))
    {:ok, view, _html} = live(conn, ~p"/")
    render_submit(view, "open", %{"path" => path})
    %{view: view, path: path, source: source}
  end

  test "opening an implicit sans document stays clean and saving does not add appearance", %{
    view: view,
    path: path
  } do
    bytes = File.read!(path)
    assert has_element?(view, "[data-dirty=false][data-drawing-font=sans]")
    assert File.read!(path) == bytes

    render_click(view, "save")
    {:ok, document} = Document.open(path)
    refute Map.has_key?(document.source, "appearance")
    assert has_element?(view, "[data-dirty=false][data-drawing-font=sans]")
  end

  test "all generic lettering choices are explicit edits that preserve geometry and metadata", %{
    view: view,
    path: path,
    source: source
  } do
    source = Map.put(source, "appearance", %{"font" => "sans", "future" => %{"keep" => true}})
    File.write!(path, Jason.encode!(source))
    render_click(view, "reload")
    render_click(view, "toggle-file-menu")

    {:ok, original} = Document.open(path)

    for font <- ~w(heading mono handwritten sans) do
      view |> form("#appearance-form", %{"font" => font}) |> render_change()
      assert has_element?(view, "[data-dirty=true][data-drawing-font=#{font}]")
      assert has_element?(view, "#drawing-font option[value=#{font}][selected]")
      {:ok, before_save} = Document.open(path)
      refute Document.drawing_font(before_save) == font

      render_click(view, "save")
      assert has_element?(view, "[data-dirty=false][data-drawing-font=#{font}]")
      {:ok, saved} = Document.open(path)
      assert saved.source["appearance"] == %{"font" => font, "future" => %{"keep" => true}}
      assert saved.graph == original.graph

      render_click(view, "reload")
      assert has_element?(view, "[data-dirty=false][data-drawing-font=#{font}]")
      render_click(view, "toggle-file-menu")
    end
  end

  test "reverting lettering clears only the lettering edit, not graph edits", %{
    view: view,
    path: path
  } do
    render_change(view, "appearance", %{"font" => "heading"})
    assert has_element?(view, "[data-dirty=true]")
    render_change(view, "appearance", %{"font" => "sans"})
    assert has_element?(view, "[data-dirty=false]")

    {:ok, document} = Document.open(path)

    {:ok, graph, _, _} =
      Graph.apply(document.graph, Change.move([%{id: "idea", x: 123.5, y: -90}]))

    send(view.pid, {:canvas_changed, graph})
    assert has_element?(view, "[data-dirty=true]")
    render_change(view, "appearance", %{"font" => "mono"})
    render_change(view, "appearance", %{"font" => "sans"})
    assert has_element?(view, "[data-dirty=true][data-drawing-font=sans]")
  end
end
