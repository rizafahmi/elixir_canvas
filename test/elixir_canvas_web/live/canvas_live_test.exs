defmodule ElixirCanvasWeb.CanvasLiveTest do
  use ElixirCanvasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ElixirCanvas.Document
  alias Hakushi.{Change, Graph}
  alias Hakushi.Test, as: CanvasTest

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

  test "document lettering changes leave explicit object roles and inherited data untouched", %{
    view: view,
    path: path,
    source: source
  } do
    source =
      source
      |> Map.put("appearance", %{"font" => "handwritten", "future" => %{"keep" => true}})
      |> put_in(["nodes", Access.at(0), "data", "font"], "sans")

    File.write!(path, Jason.encode!(source))
    render_click(view, "reload")
    assert {:ok, original} = Document.open(path)

    for font <- ~w(mono heading handwritten sans) do
      render_change(view, "appearance", %{"font" => font})
      render_click(view, "save")
      render_click(view, "reload")
      assert {:ok, reopened} = Document.open(path)
      assert Document.drawing_font(reopened) == font
      assert reopened.graph == original.graph
      assert Graph.node(reopened.graph, "idea").data["font"] == "sans"
      refute Map.has_key?(Graph.node(reopened.graph, "make").data, "font")
      assert reopened.source["appearance"]["future"] == %{"keep" => true}
    end
  end

  test "selection typography applies as one undoable edit without changing geometry",
       %{
         view: view,
         path: path,
         source: source
       } do
    line = %{
      "id" => "line",
      "type" => "shape-line",
      "x" => 20,
      "y" => 220,
      "width" => 220,
      "height" => 100,
      "data" => %{"from" => [12, 12], "to" => [208, 88], "stroke" => "surface", "arrow" => "both"}
    }

    source =
      source
      |> Map.put("appearance", %{"font" => "handwritten", "future" => %{"keep" => true}})
      |> put_in(["nodes", Access.at(0), "data", "font"], "sans")
      |> put_in(["nodes", Access.at(0), "data", "future"], %{"keep" => true})
      |> put_in(["nodes", Access.at(1), "data", "kind"], "text")
      |> Map.update!("nodes", &(&1 ++ [line]))

    File.write!(path, Jason.encode!(source))
    render_click(view, "reload")
    board = board_id(view)
    assert {:ok, original} = Document.open(path)
    selected = ["idea", "make", "line"]

    assert :ok =
             CanvasTest.edit(view, board, selected, "style", %{"style" => %{"font" => "mono"}})

    assert has_element?(view, "[data-dirty=true]")
    assert :ok = CanvasTest.undo(view, board)
    assert has_element?(view, "[data-dirty=false]")
    assert :ok = CanvasTest.redo(view, board)
    render_click(view, "save")
    assert {:ok, overridden} = Document.open(path)

    for id <- ~w(idea make) do
      authored = Graph.node(original.graph, id)
      expected = %{authored | data: Map.put(authored.data, "font", "mono")}
      assert Graph.node(overridden.graph, id) == expected
    end

    assert Graph.node(overridden.graph, "line") == Graph.node(original.graph, "line")
    assert overridden.graph.edges == original.graph.edges
    assert overridden.source["appearance"] == original.source["appearance"]
  end

  test "object role changes preserve true text-edit growth, undo, save, and reload", %{
    view: view,
    path: path,
    source: source
  } do
    source =
      source
      |> put_in(["nodes", Access.at(1), "data", "kind"], "text")
      |> put_in(["nodes", Access.at(1), "data", "font"], "handwritten")

    File.write!(path, Jason.encode!(source))
    render_click(view, "reload")
    board = board_id(view)
    assert {:ok, document} = Document.open(path)
    original = Graph.node(document.graph, "make")
    initial_box = {original.x, original.y, original.width, original.height}
    text = "First line\nSecond line\nThird line"
    grown_box = [original.x, original.y, original.width + 20, original.height + 80]

    assert :ok =
             CanvasTest.edit(view, board, "make", "style", %{"style" => %{"font" => "heading"}})

    assert node_box(view, board, "make") == initial_box

    assert :ok =
             CanvasTest.edit(view, board, "make", "text", %{"value" => text, "box" => grown_box})

    assert node_box(view, board, "make") == List.to_tuple(grown_box)
    assert :ok = CanvasTest.undo(view, board)
    assert node_box(view, board, "make") == initial_box
    assert :ok = CanvasTest.undo(view, board)
    assert has_element?(view, "[data-dirty=false]")
    assert :ok = CanvasTest.redo(view, board)
    assert node_box(view, board, "make") == initial_box
    assert :ok = CanvasTest.redo(view, board)
    assert node_box(view, board, "make") == List.to_tuple(grown_box)

    render_click(view, "save")
    render_click(view, "reload")
    assert {:ok, reopened} = Document.open(path)
    edited = Graph.node(reopened.graph, "make")
    assert {edited.x, edited.y, edited.width, edited.height} == List.to_tuple(grown_box)
    expected_data = original.data |> Map.put("font", "heading") |> Map.put("text", text)
    assert edited.data == expected_data
    assert node_box(view, board_id(view), "make") == List.to_tuple(grown_box)
  end

  defp board_id(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".drawing-board")
    |> LazyHTML.attribute("id")
    |> List.first()
  end

  defp node_box(view, board, id) do
    node = view |> CanvasTest.nodes(board) |> Enum.find(&(&1.id == id))
    {node.x, node.y, node.width, node.height}
  end
end
