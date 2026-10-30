defmodule ElixirCanvasWeb.DrawingShapes do
  @moduledoc "Editable shapes with the canvas's explicit, unfilled drawing defaults."
  use Hakushi.Kit

  alias Hakushi.Kits.Shapes

  @impl true
  def name, do: "drawing"

  @impl true
  defdelegate title(messages), to: Shapes
  @impl true
  defdelegate icon(), to: Shapes
  @impl true
  defdelegate types(), to: Shapes
  @impl true
  defdelegate elements(messages), to: Shapes
  @impl true
  defdelegate node(assigns), to: Shapes
  @impl true
  defdelegate edit(action, params, data), to: Shapes
  @impl true
  defdelegate resizable?(type), to: Shapes
  @impl true
  defdelegate tools(messages), to: Shapes
  @impl true
  defdelegate styles(messages), to: Shapes
  @impl true
  defdelegate label(node, messages), to: Shapes

  def defaults(kind) do
    %{
      "fill" => "none",
      "stroke" => if(kind == "text", do: "none", else: "ink"),
      "width" => 2,
      "radius" => 8,
      "align" => "left"
    }
  end

  @impl true
  def new_node("rect", {x, y}, _messages),
    do: Shapes.shape("rect", [x, y, 0, 0], defaults("rect"))

  def new_node(_item, _position, _messages), do: nil

  @impl true
  def drawn(tool, params, messages) do
    params = Map.put(params, "style", Map.merge(defaults(tool), params["style"] || %{}))
    Shapes.drawn(tool, params, messages)
  end
end
