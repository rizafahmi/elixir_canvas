defmodule ElixirCanvasWeb.DrawingShapesTest do
  use ExUnit.Case, async: true

  alias ElixirCanvasWeb.DrawingShapes

  test "theme-relative shape edits preserve authored geometry, corners, and text intent" do
    node =
      DrawingShapes.drawn(
        "rect",
        %{
          "box" => [10, 20, 180, 90],
          "style" => %{"fill" => "surface", "stroke" => "accent", "radius" => 8, "size" => "l"}
        },
        %{}
      )

    assert node.data["fill"] == "surface"
    assert node.data["stroke"] == "accent"
    assert node.data["radius"] == 8

    {:ok, data} =
      DrawingShapes.edit(
        "style",
        %{"style" => %{"fill" => "accent", "stroke" => "surface", "width" => 999}},
        node.data
      )

    edited = %{node | data: data}
    assert edited.data["fill"] == "accent"
    assert edited.data["stroke"] == "surface"
    assert Map.drop(edited.data, ~w(fill stroke)) == Map.drop(node.data, ~w(fill stroke))
    assert Map.delete(edited, :data) == Map.delete(node, :data)

    {:ok, unchanged} =
      DrawingShapes.edit("style", %{"style" => %{"fill" => "#c5f82a"}}, edited.data)

    assert unchanged == edited.data
  end

  test "theme-relative edits can add omitted optional styles without adding line fills" do
    shape = %{"kind" => "rect", "text" => "Minimal shape"}
    line = %{"from" => [0, 0], "to" => [120, 80]}
    style = %{"fill" => "accent", "stroke" => "surface"}

    assert {:ok, edited_shape} = DrawingShapes.edit("style", %{"style" => style}, shape)
    assert edited_shape == Map.merge(shape, style)

    assert {:ok, edited_line} = DrawingShapes.edit("style", %{"style" => style}, line)
    assert edited_line == Map.put(line, "stroke", "surface")
  end

  test "standalone line edits change named stroke without changing endpoints or acquiring fill" do
    node =
      DrawingShapes.drawn(
        "line",
        %{
          "points" => [[10, 20], [210, 120]],
          "style" => %{"stroke" => "accent", "arrow" => "both"}
        },
        %{}
      )

    assert node.type == "shape-line"
    assert node.data["stroke"] == "accent"

    {:ok, data} =
      DrawingShapes.edit(
        "style",
        %{"style" => %{"stroke" => "surface", "fill" => "accent", "radius" => 8}},
        node.data
      )

    edited = %{node | data: data}
    assert edited.data["stroke"] == "surface"
    refute Map.has_key?(edited.data, "fill")
    refute Map.has_key?(edited.data, "radius")
    assert Map.drop(edited.data, ["stroke"]) == Map.drop(node.data, ["stroke"])
    assert Map.delete(edited, :data) == Map.delete(node, :data)

    {:ok, unchanged} =
      DrawingShapes.edit("style", %{"style" => %{"stroke" => "#ecece6"}}, edited.data)

    assert unchanged == edited.data
  end

  test "typography overrides apply to every text-bearing shape without changing other data" do
    for kind <- ~w(rect ellipse diamond triangle text) do
      node = DrawingShapes.drawn(kind, %{"box" => [-25.5, 80, 241.5, 105]}, %{})

      original =
        Map.merge(node.data, %{
          "text" => "Keep this label",
          "rotation" => 17,
          "future" => %{"reviewed" => true}
        })

      for font <- ~w(sans heading mono handwritten) do
        assert {:ok, edited} =
                 DrawingShapes.edit("style", %{"style" => %{"font" => font}}, original)

        assert edited == Map.put(original, "font", font)
      end
    end
  end

  test "creation keeps explicit roles without materializing inherited fonts or changing the box" do
    for kind <- ~w(rect ellipse diamond triangle text) do
      params = %{"box" => [-50.5, 25, 240, 120], "style" => %{"radius" => 8, "size" => "l"}}
      inherited = DrawingShapes.drawn(kind, params, %{})
      refute Map.has_key?(inherited.data, "font")

      for font <- ~w(sans heading mono handwritten) do
        chosen = DrawingShapes.drawn(kind, put_in(params, ["style", "font"], font), %{})
        assert Map.delete(chosen, :data) == Map.delete(inherited, :data)
        assert Map.delete(chosen.data, "font") == inherited.data

        assert chosen.data["font"] == font
      end
    end

    refute Map.has_key?(DrawingShapes.new_node("rect", {10, 20}, %{}).data, "font")
  end

  test "font edits coexist with semantic colors and authored corners" do
    original = %{"kind" => "rect", "text" => "Keep me", "rotation" => 23, "future" => [1, 2]}
    style = %{"font" => "mono", "fill" => "accent", "stroke" => "surface", "radius" => 8}

    assert {:ok, edited} = DrawingShapes.edit("style", %{"style" => style}, original)
    assert edited == Map.merge(original, style)
  end

  test "invalid roles and resolved families refuse an edit or creation instead of being saved" do
    original = %{"kind" => "text", "text" => "Unchanged", "font" => "heading"}

    for font <- [
          nil,
          "",
          "inherit",
          "serif",
          "Sans",
          "Mona Sans",
          "Unbounded",
          "Monaspace Neon",
          "Amatic SC",
          1,
          true,
          [],
          %{}
        ] do
      assert :error ==
               DrawingShapes.edit(
                 "style",
                 %{"style" => %{"font" => font, "fill" => "accent"}},
                 original
               )

      assert nil ==
               DrawingShapes.drawn(
                 "text",
                 %{"box" => [0, 0, 180, 40], "style" => %{"font" => font}},
                 %{}
               )
    end
  end

  test "line creation and edits never acquire a typography override" do
    params = %{"points" => [[10, 20], [210, 120]], "style" => %{"arrow" => "both"}}
    original = DrawingShapes.drawn("line", params, %{})

    for font <- ~w(sans heading mono handwritten) do
      chosen = DrawingShapes.drawn("line", put_in(params, ["style", "font"], font), %{})
      assert chosen == original

      assert {:ok, edited} =
               DrawingShapes.edit("style", %{"style" => %{"font" => font}}, original.data)

      assert edited == original.data
      refute Map.has_key?(edited, "font")
    end
  end
end
