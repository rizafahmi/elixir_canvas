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
end
