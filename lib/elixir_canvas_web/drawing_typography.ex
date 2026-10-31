defmodule ElixirCanvasWeb.DrawingTypography do
  @moduledoc false
  use Phoenix.Component

  alias Hakushi.Kits.Shapes

  def node(%{node: %{type: "shape-line"}} = assigns), do: Shapes.node(assigns)

  def node(assigns) do
    assigns = assign(assigns, :font, Hakushi.Kit.get(assigns.node.data, "font"))

    ~H"""
    <div class="drawing-typography" data-drawing-font={@font}>
      <Shapes.node
        node={@node}
        canvas={@canvas}
        readonly={@readonly}
        target={@target}
        messages={@messages}
      />
    </div>
    """
  end
end
