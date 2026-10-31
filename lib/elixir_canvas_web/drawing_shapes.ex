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
  defdelegate resizable?(type), to: Shapes
  @impl true
  defdelegate tools(messages), to: Shapes
  @impl true
  defdelegate label(node, messages), to: Shapes

  @theme_colors ~w(accent surface)

  @impl true
  def styles(messages) do
    Enum.map(Shapes.styles(messages), fn
      %{kind: "color"} = group ->
        options =
          Enum.map(@theme_colors, fn color ->
            %{value: color, label: String.capitalize(color)}
          end)

        %{group | options: group.options ++ options}

      group ->
        group
    end)
  end

  @impl true
  def edit("style", %{"style" => style} = params, data) when is_map(style) do
    with {:ok, edited} <- Shapes.edit("style", params, data) do
      {:ok, theme_colors(edited, style)}
    end
  end

  def edit(action, params, data), do: Shapes.edit(action, params, data)

  # Optional style fields may be absent; shape kind, not key presence, defines
  # whether fill is meaningful. Standalone lines accept only stroke.
  defp theme_colors(data, style) do
    keys = if Map.has_key?(data, "kind"), do: ~w(fill stroke), else: ~w(stroke)

    Enum.reduce(keys, data, fn key, data ->
      if style[key] in @theme_colors,
        do: Map.put(data, key, style[key]),
        else: data
    end)
  end

  def defaults(kind) do
    %{
      "fill" => "none",
      "stroke" => if(kind == "text", do: "none", else: "ink"),
      "width" => 2,
      "radius" => 0,
      "align" => "left"
    }
  end

  @impl true
  def new_node("rect", {x, y}, _messages),
    do: Shapes.shape("rect", [x, y, 0, 0], defaults("rect"))

  def new_node(_item, _position, _messages), do: nil

  @impl true
  def drawn(tool, params, messages) do
    style = Map.merge(defaults(tool), params["style"] || %{})
    style = if tool == "line", do: Map.take(style, ~w(stroke width dash arrow)), else: style
    params = Map.put(params, "style", style)

    case Shapes.drawn(tool, params, messages) do
      %{data: data} = node -> %{node | data: theme_colors(data, params["style"])}
      result -> result
    end
  end
end
