defmodule ElixirCanvas.DocumentTest do
  use ExUnit.Case, async: true

  alias ElixirCanvas.Document
  alias Hakushi.{Change, Graph}

  @moduletag :tmp_dir

  setup %{tmp_dir: directory} do
    path = Path.join(directory, "ideas.json")
    File.cp!(Path.expand("../fixtures/document.json", __DIR__), path)
    {:ok, document} = Document.open(path)
    %{path: path, document: document}
  end

  test "selected file bytes load real graph content without acquiring a server path", %{
    path: path,
    document: document
  } do
    bytes = File.read!(path)

    for persistence <- [:browser_file, :save_copy] do
      assert {:ok, selected} = Document.open_selected("ideas.json", bytes, persistence)
      assert selected.path == nil
      assert selected.filename == "ideas.json"
      assert selected.persistence == persistence
      assert selected.revision == :crypto.hash(:sha256, bytes)
      assert selected.graph == document.graph
      assert Graph.node(selected.graph, "idea").data["text"] == "Start with an idea"
      assert Graph.edge(selected.graph, "idea-to-make").target == "make"
      assert Document.status(selected) == :client_managed

      assert {:ok, moved, _, _} =
               Graph.apply(selected.graph, Change.move([%{id: "idea", x: 190, y: -30}]))

      assert {:error, _reason} = Document.save(selected, moved)
      assert File.read!(path) == bytes
    end
  end

  test "selected content uses canvas validation without rewriting the existing file", %{
    path: path,
    document: document
  } do
    original = File.read!(path)

    for invalid <- [
          "{",
          "[]",
          <<0xEF, 0xBB, 0xBF>> <> original,
          Jason.encode!(Map.put(document.source, "version", 2)),
          Jason.encode!(Map.put(document.source, "appearance", %{"font" => "Mona Sans"})),
          Jason.encode!(
            put_in(document.source, ["nodes", Access.at(0), "data", "font"], "serif")
          ),
          Jason.encode!(Map.put(document.source, "nodes", []))
        ] do
      assert {:error, _reason} = Document.open_selected("ideas.json", invalid, :save_copy)
      assert File.read!(path) == original
    end
  end

  test "preparing selected edits preserves portable roles and unknown metadata without committing",
       %{path: path, document: document} do
    original = File.read!(path)

    source =
      document.source
      |> Map.put("author", %{"name" => "Future me"})
      |> Map.put("appearance", %{"font" => "mono", "future" => %{"keep" => true}})
      |> Map.put("paper", %{"background" => "dots", "grid" => 20, "annotation" => "Keep paper"})
      |> put_in(["nodes", Access.at(0), "annotation"], %{"reviewed" => true})
      |> put_in(["nodes", Access.at(0), "data", "font"], "heading")
      |> put_in(["nodes", Access.at(0), "data", "future"], %{"intent" => "authored"})
      |> put_in(["edges", Access.at(0), "annotation"], %{"keep" => true})

    opened_bytes = Jason.encode!(source)

    assert {:ok, selected} = Document.open_selected("picked.json", opened_bytes, :browser_file)
    original_node = Graph.node(selected.graph, "idea")

    assert {:ok, moved, _, _} =
             Graph.apply(selected.graph, Change.move([%{id: "idea", x: -125.5, y: 80.25}]))

    assert {:ok, bytes, prepared} = Document.prepare_save(selected, moved)
    assert prepared.path == nil
    assert prepared.filename == "picked.json"
    assert prepared.persistence == :browser_file
    assert prepared.graph == moved
    assert prepared.revision == :crypto.hash(:sha256, bytes)
    refute prepared.revision == selected.revision
    assert selected.graph != moved
    assert selected.source == source
    assert selected.revision == :crypto.hash(:sha256, opened_bytes)
    assert File.read!(path) == original

    assert {:ok, reloaded} = Document.open_selected("picked.json", bytes, :browser_file)
    assert reloaded.graph == moved
    assert reloaded.source == prepared.source
    assert reloaded.source["author"] == source["author"]
    assert reloaded.source["appearance"] == source["appearance"]
    assert reloaded.source["paper"]["annotation"] == "Keep paper"
    assert hd(reloaded.source["nodes"])["annotation"] == %{"reviewed" => true}
    assert hd(reloaded.source["edges"])["annotation"] == %{"keep" => true}
    assert Document.drawing_font(reloaded) == "mono"
    assert Graph.node(reloaded.graph, "idea") == %{original_node | x: -125.5, y: 80.25}
    refute Map.has_key?(Graph.node(reloaded.graph, "make").data, "font")

    assert {:ok, deleted, _, _} = Graph.apply(moved, Change.delete(nodes: ["make"]))
    assert {:ok, deleted_bytes, _prepared} = Document.prepare_save(prepared, deleted)
    persisted = Jason.decode!(deleted_bytes)
    assert [%{"id" => "idea", "annotation" => %{"reviewed" => true}}] = persisted["nodes"]
    assert persisted["edges"] == []
  end

  test "an invalid prepared graph cannot become an acknowledged document", %{path: path} do
    bytes = File.read!(path)
    assert {:ok, selected} = Document.open_selected("ideas.json", bytes, :browser_file)
    node = Graph.node(selected.graph, "idea")

    assert {:ok, invalid, _, _} =
             Graph.apply(
               selected.graph,
               Change.update(
                 nodes: [%{id: node.id, data: Map.put(node.data, "font", "Mona Sans")}]
               )
             )

    assert {:error, _reason} = Document.prepare_save(selected, invalid)
    assert selected.revision == :crypto.hash(:sha256, bytes)
    refute Map.has_key?(Graph.node(selected.graph, "idea").data, "font")
    assert File.read!(path) == bytes
  end

  test "prepared copy bytes can be opened as a separate server file without changing the original",
       %{path: path, tmp_dir: directory} do
    original = File.read!(path)
    assert {:ok, selected} = Document.open_selected("ideas.json", original, :save_copy)

    assert {:ok, moved, _, _} =
             Graph.apply(selected.graph, Change.move([%{id: "idea", x: 250, y: 120}]))

    assert {:ok, bytes, prepared} = Document.prepare_save(selected, moved)
    copy_path = Path.join(directory, "saved-copy.json")
    File.write!(copy_path, bytes, [:exclusive])
    assert {:ok, reopened} = Document.open(copy_path)
    assert reopened.persistence == :server_file
    assert reopened.path == copy_path
    assert Graph.node(reopened.graph, "idea").x == 250
    assert reopened.graph == prepared.graph
    assert prepared.persistence == :save_copy
    assert prepared.path == nil
    assert Document.status(selected) == :client_managed
    assert File.read!(path) == original
  end

  test "a moved and resized shape retains text, styles, connections, and stacking order after reopening",
       %{document: document} do
    change = Change.move([%{id: "idea", x: -125.5, y: 80, width: 300, height: 180}])
    {:ok, graph, _, _} = Graph.apply(document.graph, change)
    {:ok, saved} = Document.save(document, graph)
    {:ok, reopened} = Document.open(saved.path)

    idea = Graph.node(reopened.graph, "idea")
    assert {idea.x, idea.y, idea.width, idea.height} == {-125.5, 80, 300, 180}
    assert idea.data["text"] == "Start with an idea"
    assert idea.data["fill"] == "yellow"
    assert reopened.graph.node_order == ["idea", "make"]
    edge = Graph.edge(reopened.graph, "idea-to-make")

    assert {edge.source, edge.source_handle, edge.target, edge.target_handle} ==
             {"idea", "right", "make", "left"}

    assert Document.status(saved) == :unchanged
  end

  test "a self-loop retains distinct handles and metadata through move, undo, save, and reload",
       %{document: document} do
    edge = %{
      id: "idea-loop",
      source: "idea",
      source_handle: "right",
      target: "idea",
      target_handle: "top",
      path: :bezier,
      label: "Try again",
      data: %{"stroke" => "violet", "review" => %{"approved" => true}}
    }

    rules = Hakushi.Rules.new(loops: true)

    {:ok, connected, _, disconnect} =
      Hakushi.Commit.check_and_apply(document.graph, Change.connect(edge), rules)

    original_edge = Graph.edge(connected, "idea-loop")
    original_node = Graph.node(connected, "idea")

    {:ok, moved, _, undo_move} =
      Graph.apply(
        connected,
        Change.move([%{id: "idea", x: 425, y: -80, width: 320, height: 190}])
      )

    assert Graph.edge(moved, "idea-loop") == original_edge
    {:ok, restored, _, redo_move} = Graph.apply(moved, undo_move)
    assert Graph.node(restored, "idea") == original_node
    assert Graph.edge(restored, "idea-loop") == original_edge
    {:ok, moved_again, _, _} = Graph.apply(restored, redo_move)

    {:ok, saved} = Document.save(document, moved_again)
    {:ok, reopened} = Document.open(saved.path)
    loop = Graph.edge(reopened.graph, "idea-loop")

    assert loop == original_edge

    assert {loop.source, loop.source_handle, loop.target, loop.target_handle} ==
             {"idea", "right", "idea", "top"}

    node = Graph.node(reopened.graph, "idea")
    assert {node.x, node.y, node.width, node.height} == {425, -80, 320, 190}

    {:ok, disconnected, _, reconnect} = Graph.apply(reopened.graph, disconnect)
    refute Graph.edge(disconnected, "idea-loop")
    {:ok, reconnected, _, _} = Graph.apply(disconnected, reconnect)
    assert Graph.edge(reconnected, "idea-loop") == original_edge
  end

  test "a stale save cannot overwrite external content and can recover by reopening", %{
    path: path,
    document: document
  } do
    external = File.read!(path) |> String.replace("Start with an idea", "An external edit")
    File.write!(path, external)

    assert Document.status(document) == :changed
    assert {:error, reason} = Document.save(document, document.graph)
    assert reason =~ "changed on disk"
    assert File.read!(path) == external

    {:ok, fresh} = Document.open(path)
    assert Graph.node(fresh.graph, "idea").data["text"] == "An external edit"
    assert {:ok, _} = Document.save(fresh, fresh.graph)
  end

  test "two app sessions cannot both save against the same old revision", %{document: document} do
    tasks =
      for x <- [150, 300] do
        Task.async(fn ->
          {:ok, graph, _, _} =
            Graph.apply(document.graph, Change.move([%{id: "idea", x: x, y: 0}]))

          Document.save(document, graph)
        end)
      end

    results = Enum.map(tasks, &Task.await/1)
    assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:error, reason}] = Enum.filter(results, &match?({:error, _}, &1))
    assert reason =~ "changed on disk"
    {:ok, reopened} = Document.open(document.path)
    assert Graph.node(reopened.graph, "idea").x == Graph.node(winner.graph, "idea").x
  end

  test "unknown metadata survives a graph edit without resurrecting removed supported fields", %{
    path: path
  } do
    source = path |> File.read!() |> Jason.decode!()
    [idea, make] = source["nodes"]

    source =
      source
      |> Map.put("author", "Future me")
      |> Map.put("nodes", [Map.put(idea, "annotation", %{"reviewed" => true}), make])

    source =
      Map.put(source, "paper", %{
        "background" => "dots",
        "grid" => 20,
        "annotation" => "Keep this"
      })

    File.write!(path, Jason.encode!(source))
    {:ok, document} = Document.open(path)
    {:ok, graph, _, _} = Graph.apply(document.graph, Change.delete(nodes: ["make"]))
    {:ok, _} = Document.save(document, graph)
    saved = path |> File.read!() |> Jason.decode!()

    assert saved["author"] == "Future me"
    assert [%{"id" => "idea", "annotation" => %{"reviewed" => true}}] = saved["nodes"]
    assert saved["edges"] == []
    assert saved["paper"]["annotation"] == "Keep this"
  end

  test "a missing source is not recreated by saving stale state", %{
    path: path,
    document: document
  } do
    File.rm!(path)
    assert Document.status(document) == :unavailable
    assert {:error, _} = Document.save(document, document.graph)
    refute File.exists?(path)
  end

  test "creating a document never clobbers an existing file", %{path: path, tmp_dir: directory} do
    original = File.read!(path)
    assert {:error, _} = Document.create(path)
    assert File.read!(path) == original

    blank_path = Path.join(directory, "blank.json")
    assert {:ok, blank} = Document.create(blank_path)
    assert blank.graph.nodes == %{}
    assert blank.graph.edges == %{}
    assert blank.path == blank_path
    assert blank.filename == "blank.json"
    assert blank.persistence == :server_file

    assert {:ok, populated, _, _} =
             Graph.apply(
               blank.graph,
               Change.add([
                 %{
                   id: "created-idea",
                   type: "shape",
                   x: 30,
                   y: -40,
                   width: 250,
                   height: 140,
                   data: %{"kind" => "rect", "text" => "A new file's first idea"}
                 }
               ])
             )

    assert {:ok, saved} = Document.save(blank, populated)
    assert {:ok, reopened} = Document.open(saved.path)
    assert reopened.filename == "blank.json"
    assert reopened.persistence == :server_file
    assert Graph.node(reopened.graph, "created-idea").data["text"] == "A new file's first idea"
    assert File.read!(path) == original
  end

  test "legacy documents keep their implicit sans font after an unrelated save", %{
    path: path
  } do
    source = path |> File.read!() |> Jason.decode!() |> Map.delete("appearance")
    File.write!(path, Jason.encode!(source))
    {:ok, document} = Document.open(path)

    assert Document.drawing_font(document) == "sans"
    refute Map.has_key?(document.source, "appearance")

    {:ok, graph, _, _} =
      Graph.apply(document.graph, Change.move([%{id: "idea", x: 125, y: 80}]))

    {:ok, saved} = Document.save(document, graph)
    {:ok, reopened} = Document.open(path)
    assert Document.drawing_font(saved) == "sans"
    assert Document.drawing_font(reopened) == "sans"
    refute Map.has_key?(saved.source, "appearance")
    refute Map.has_key?(reopened.source, "appearance")
    refute Map.has_key?(Jason.decode!(File.read!(path)), "appearance")
    assert Graph.node(reopened.graph, "idea").x == 125
  end

  test "appearance objects and unknown metadata survive unrelated graph edits", %{path: path} do
    original = path |> File.read!() |> Jason.decode!()

    for appearance <- [
          %{},
          %{"font" => "sans"},
          %{"font" => "heading"},
          %{"font" => "mono"},
          %{"font" => "handwritten"},
          %{"future" => %{"palette" => ["ink", "blue"], "enabled" => true}},
          %{"font" => "handwritten", "future" => %{"custom" => nil}}
        ] do
      source = Map.put(original, "appearance", appearance)
      File.write!(path, Jason.encode!(source))
      {:ok, document} = Document.open(path)
      assert Document.drawing_font(document) == Map.get(appearance, "font", "sans")

      {:ok, graph, _, _} =
        Graph.apply(document.graph, Change.move([%{id: "idea", x: 150, y: 90}]))

      {:ok, saved} = Document.save(document, graph)
      {:ok, reopened} = Document.open(path)
      assert saved.source["appearance"] == appearance
      assert reopened.source["appearance"] == appearance
      assert Document.drawing_font(reopened) == Map.get(appearance, "font", "sans")
      assert Jason.decode!(File.read!(path))["appearance"] == appearance
      assert Graph.node(reopened.graph, "idea").x == 150
    end
  end

  test "invalid appearance objects and font values are rejected without rewriting", %{path: path} do
    original = path |> File.read!() |> Jason.decode!()

    for appearance <- [
          nil,
          [],
          "handwritten",
          1,
          false,
          %{"font" => nil},
          %{"font" => ""},
          %{"font" => "inherit"},
          %{"font" => "serif"},
          %{"font" => "Sans"},
          %{"font" => "Schibsted Grotesk"},
          %{"font" => "Mona Sans"},
          %{"font" => "Unbounded"},
          %{"font" => "Martian Mono"},
          %{"font" => "Monaspace Neon"},
          %{"font" => "Amatic SC"},
          %{"font" => "body"},
          %{"font" => "monospace"},
          %{"font" => 1},
          %{"font" => true},
          %{"font" => []},
          %{"font" => %{}}
        ] do
      bytes = original |> Map.put("appearance", appearance) |> Jason.encode!()
      File.write!(path, bytes)
      assert {:error, _reason} = Document.open(path)
      assert File.read!(path) == bytes
    end
  end

  test "portable colors and typography roundtrip without changing geometry or unknown metadata",
       %{
         path: path
       } do
    original = path |> File.read!() |> Jason.decode!()

    for font <- ~w(sans heading mono handwritten),
        color <- ~w(none ink gray blue green yellow red violet accent surface) do
      source =
        original
        |> Map.put("appearance", %{"font" => font, "future" => %{"intent" => "diagram"}})
        |> put_in(["nodes", Access.at(0), "x"], -125.5)
        |> put_in(["nodes", Access.at(0), "width"], 301.25)
        |> put_in(["nodes", Access.at(0), "data", "fill"], color)
        |> put_in(["nodes", Access.at(0), "data", "stroke"], color)
        |> put_in(["nodes", Access.at(0), "data", "rotation"], 17)
        |> put_in(["nodes", Access.at(0), "data", "future"], %{"label" => "portable"})

      bytes = Jason.encode!(source)
      File.write!(path, bytes)
      {:ok, document} = Document.open(path)
      assert File.read!(path) == bytes
      assert Document.status(document) == :unchanged
      assert document.source == source

      {:ok, _saved} = Document.save(document, document.graph)
      {:ok, reopened} = Document.open(path)
      assert reopened.source["appearance"] == source["appearance"]
      assert length(reopened.source["nodes"]) == length(source["nodes"])
      assert length(reopened.source["edges"]) == length(source["edges"])

      for {saved_node, original_node} <- Enum.zip(reopened.source["nodes"], source["nodes"]) do
        assert Map.take(saved_node, Map.keys(original_node)) == original_node
      end

      for {saved_edge, original_edge} <- Enum.zip(reopened.source["edges"], source["edges"]) do
        assert Map.take(saved_edge, Map.keys(original_edge)) == original_edge
      end

      assert Document.drawing_font(reopened) == font
    end
  end

  test "mixed object roles roundtrip without materializing inherited fonts or altering geometry",
       %{
         path: path
       } do
    original = path |> File.read!() |> Jason.decode!()
    [template | _] = original["nodes"]

    nodes =
      for {kind, index} <- Enum.with_index(~w(rect ellipse diamond triangle text)) do
        font = Enum.at([nil, "sans", "heading", "mono", "handwritten"], index)

        node =
          template
          |> Map.merge(%{"id" => "role-#{index}", "x" => -125.5 + index * 270, "width" => 301.25})
          |> put_in(["data", "kind"], kind)
          |> put_in(["data", "rotation"], 17)
          |> put_in(["data", "future"], %{"intent" => "portable"})

        if font, do: put_in(node, ["data", "font"], font), else: node
      end

    source =
      original
      |> Map.put("nodes", nodes)
      |> Map.put("edges", [])
      |> Map.put("appearance", %{"font" => "handwritten", "future" => %{"keep" => true}})

    File.write!(path, Jason.encode!(source))
    assert {:ok, document} = Document.open(path)
    assert {:ok, _saved} = Document.save(document, document.graph)
    assert {:ok, reopened} = Document.open(path)
    assert reopened.graph == document.graph
    assert reopened.source["appearance"] == source["appearance"]

    for {saved, authored} <- Enum.zip(reopened.source["nodes"], nodes) do
      assert Map.take(saved, Map.keys(authored)) == authored
    end

    refute Map.has_key?(Graph.node(reopened.graph, "role-0").data, "font")
    assert Graph.node(reopened.graph, "role-1").data["font"] == "sans"
  end

  test "removing an object override survives saving and reopening without restoring the old font",
       %{
         path: path
       } do
    source =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("appearance", %{"font" => "mono"})
      |> put_in(["nodes", Access.at(0), "data", "font"], "heading")
      |> put_in(["nodes", Access.at(0), "data", "future"], %{"keep" => true})

    File.write!(path, Jason.encode!(source))
    assert {:ok, document} = Document.open(path)
    original = Graph.node(document.graph, "idea")
    reset = Map.delete(original.data, "font")

    assert {:ok, graph, _, inverse} =
             Graph.apply(document.graph, Change.update(nodes: [%{id: "idea", data: reset}]))

    assert {:ok, _saved} = Document.save(document, graph)
    assert {:ok, reopened} = Document.open(path)
    assert Graph.node(reopened.graph, "idea") == %{original | data: reset}
    refute Map.has_key?(Graph.node(reopened.graph, "idea").data, "font")
    assert reopened.source["appearance"] == source["appearance"]

    assert {:ok, restored, _, _} = Graph.apply(graph, inverse)
    assert restored == document.graph
  end

  test "invalid object font roles and concrete families are rejected without rewriting", %{
    path: path
  } do
    original = path |> File.read!() |> Jason.decode!()

    for kind <- ~w(rect text),
        font <- [
          nil,
          "",
          "inherit",
          "body",
          "serif",
          "Sans",
          "Mona Sans",
          "Unbounded",
          "Monaspace Neon",
          "Amatic SC",
          400,
          false,
          [],
          %{}
        ] do
      source =
        original
        |> put_in(["nodes", Access.at(0), "data", "kind"], kind)
        |> put_in(["nodes", Access.at(0), "data", "font"], font)

      bytes = Jason.encode!(source)
      File.write!(path, bytes)
      assert {:error, _reason} = Document.open(path)
      assert File.read!(path) == bytes
    end
  end

  test "standalone lines accept no object font field, even a generic role" do
    line = %{
      "id" => "line",
      "type" => "shape-line",
      "x" => 10,
      "y" => 20,
      "width" => 200,
      "height" => 100,
      "data" => %{"from" => [12, 12], "to" => [188, 88], "stroke" => "accent"}
    }

    source = %{"version" => 1, "nodes" => [line], "edges" => []}
    assert {:ok, _graph, _source} = Document.decode(Jason.encode!(source))

    for font <- [nil, "inherit" | ~w(sans heading mono handwritten)] do
      invalid = put_in(source, ["nodes", Access.at(0), "data", "font"], font)
      assert {:error, _reason} = Document.decode(Jason.encode!(invalid))
    end
  end

  test "a moved reverse-direction straight line preserves authored endpoints and metadata after reopening",
       %{path: path, document: document} do
    line = %{
      "id" => "standalone-line",
      "type" => "shape-line",
      "x" => -300.25,
      "y" => -40.5,
      "width" => 264.25,
      "height" => 196.5,
      "data" => %{
        "from" => [252.25, 12],
        "to" => [12, 184.5],
        "stroke" => "accent",
        "width" => 2,
        "dash" => false,
        "arrow" => "none",
        "future" => %{"intent" => "authored line"}
      },
      "annotation" => %{"keep" => true}
    }

    source = Map.update!(document.source, "nodes", &(&1 ++ [line]))
    bytes = Jason.encode!(source)
    File.write!(path, bytes)
    assert {:ok, authored} = Document.open(path)
    assert File.read!(path) == bytes

    assert {:ok, moved, _change, _inverse} =
             Graph.apply(authored.graph, Change.move([%{id: line["id"], x: -125.5, y: 80.25}]))

    assert {:ok, saved} = Document.save(authored, moved)
    assert {:ok, reopened} = Document.open(saved.path)
    persisted = Graph.node(reopened.graph, line["id"])

    assert {persisted.x, persisted.y, persisted.width, persisted.height} ==
             {-125.5, 80.25, 264.25, 196.5}

    assert persisted.data == line["data"]
    assert reopened.graph == moved
    assert Graph.nodes(reopened.graph) == Graph.nodes(document.graph) ++ [persisted]
    assert reopened.graph.edges == document.graph.edges
    saved_line = Enum.find(reopened.source["nodes"], &(&1["id"] == line["id"]))
    assert Map.take(saved_line, Map.keys(line)) == %{line | "x" => -125.5, "y" => 80.25}
    assert Document.status(reopened) == :unchanged
  end

  test "resolved colors and unsupported names are rejected without rewriting", %{path: path} do
    original = path |> File.read!() |> Jason.decode!()

    for field <- ~w(fill stroke), color <- ["#c5f82a", "rgb(10, 11, 13)", "acid", "magenta"] do
      bytes =
        original
        |> put_in(["nodes", Access.at(0), "data", field], color)
        |> Jason.encode!()

      File.write!(path, bytes)
      assert {:error, _reason} = Document.open(path)
      assert File.read!(path) == bytes
    end
  end

  test "moving a document requires no app-specific database", %{path: path, tmp_dir: directory} do
    moved = Path.join(directory, "elsewhere/renamed.json")
    File.mkdir_p!(Path.dirname(moved))
    File.rename!(path, moved)
    assert {:ok, document} = Document.open(moved)
    assert Graph.node(document.graph, "make").data["text"] == "Make room for the next one"
    assert {:ok, _} = Document.save(document, document.graph)
  end

  test "malformed, unsupported, and dangling documents are rejected rather than rewritten", %{
    path: path
  } do
    source = path |> File.read!() |> Jason.decode!()

    for invalid <- [
          "{",
          "[]",
          Jason.encode!(Map.put(source, "version", 2)),
          Jason.encode!(Map.put(source, "version", 1.0)),
          Jason.encode!(Map.put(source, "nodes", [])),
          Jason.encode!(put_in(source, ["nodes", Access.at(0), "type"], "unknown-widget")),
          Jason.encode!(put_in(source, ["nodes", Access.at(0), "width"], -1)),
          Jason.encode!(put_in(source, ["nodes", Access.at(0), "data", "kind"], "unknown-shape"))
        ] do
      File.write!(path, invalid)
      assert {:error, _} = Document.open(path)
      assert File.read!(path) == invalid
    end
  end

  test "duplicate stable IDs are rejected", %{path: path} do
    source = path |> File.read!() |> Jason.decode!()
    duplicate = put_in(source, ["nodes", Access.at(1), "id"], "idea")
    assert {:error, _} = Document.decode(Jason.encode!(duplicate))
  end

  test "text at the editor limit survives and longer text is rejected instead of truncated", %{
    path: path
  } do
    source = path |> File.read!() |> Jason.decode!()
    text = String.duplicate("🧠", 2_000)
    supported = put_in(source, ["nodes", Access.at(0), "data", "text"], text)
    assert {:ok, graph, _} = Document.decode(Jason.encode!(supported))
    assert Graph.node(graph, "idea").data["text"] == text
    too_long = put_in(supported, ["nodes", Access.at(0), "data", "text"], text <> "x")
    assert {:error, _} = Document.decode(Jason.encode!(too_long))
  end

  test "saves retain file permissions and reject symbolic links", %{
    path: path,
    document: document,
    tmp_dir: directory
  } do
    File.chmod!(path, 0o600)
    assert {:ok, _} = Document.save(document, document.graph)
    assert {:ok, stat} = File.stat(path)
    assert Bitwise.band(stat.mode, 0o777) == 0o600

    link = Path.join(directory, "link.json")
    File.ln_s!(path, link)
    assert {:error, _} = Document.open(link)
    assert {:error, _} = Document.create(link)
    assert {:ok, %{type: :symlink}} = File.lstat(link)
  end
end
