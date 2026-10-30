defmodule ElixirCanvas.Document do
  @moduledoc """
  A version-1 JSON canvas and its last-read disk revision.

  Hakushi owns graph operations; this module owns the portable file contract.
  Unknown fields are retained when supported objects are edited and saved.
  """

  alias Hakushi.Graph

  defstruct [:path, :revision, :graph, source: %{}]

  @node_fields ~w(id type x y width height data locked parent)
  @edge_fields ~w(id source source_handle target target_handle path label marker animated data)

  def open(path) do
    path = Path.expand(path)

    with {:ok, bytes} <- read_regular(path),
         {:ok, graph, source} <- decode(bytes) do
      {:ok, %__MODULE__{path: path, revision: digest(bytes), graph: graph, source: source}}
    end
  end

  def decode(bytes) do
    with {:ok, source} <- Jason.decode(bytes),
         :ok <- validate(source) do
      {:ok, Graph.load(source), source}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Invalid JSON: #{Exception.message(error)}"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in [ArgumentError, KeyError, FunctionClauseError, Protocol.UndefinedError] ->
      {:error, "Invalid canvas: #{Exception.message(error)}"}
  end

  def encode(%__MODULE__{source: source}, %Graph{} = graph) do
    dumped = Graph.dump(graph)

    source
    |> Map.drop(~w(nodes edges paper))
    |> Map.merge(dumped)
    |> Map.put("version", 1)
    |> Map.put("nodes", preserve_fields(source["nodes"], dumped["nodes"], @node_fields))
    |> Map.put("edges", preserve_fields(source["edges"], dumped["edges"], @edge_fields))
    |> preserve_paper(source["paper"])
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  def status(%__MODULE__{path: path, revision: revision}) do
    case read_regular(path) do
      {:ok, bytes} -> if digest(bytes) == revision, do: :unchanged, else: :changed
      {:error, _reason} -> :unavailable
    end
  end

  def save(%__MODULE__{} = document, %Graph{} = graph) do
    # Serialize saves from this app's tabs. External editors do not take this lock.
    :global.trans({{__MODULE__, document.path}, self()}, fn ->
      bytes = encode(document, graph)

      with {:ok, _graph, source} <- decode(bytes),
           :ok <- current_revision(document),
           :ok <- replace(document, bytes) do
        {:ok, %{document | graph: graph, revision: digest(bytes), source: source}}
      end
    end)
  end

  def create(path) do
    path = Path.expand(path)
    graph = Graph.new()
    document = %__MODULE__{path: path, graph: graph}
    bytes = encode(document, graph)

    case File.write(path, bytes, [:exclusive, :sync]) do
      :ok -> open(path)
      {:error, :eexist} -> {:error, "That file already exists. Open it instead."}
      {:error, reason} -> {:error, file_error(reason)}
    end
  end

  defp replace(document, bytes) do
    temporary = document.path <> ".#{System.unique_integer([:positive])}.tmp"

    try do
      with {:ok, stat} <- File.stat(document.path),
           :ok <- File.write(temporary, bytes, [:exclusive, :sync]),
           :ok <- File.chmod(temporary, Bitwise.band(stat.mode, 0o777)),
           :ok <- current_revision(document),
           :ok <- File.rename(temporary, document.path) do
        :ok
      else
        {:error, reason} when is_atom(reason) -> {:error, file_error(reason)}
        error -> error
      end
    after
      File.rm(temporary)
    end
  end

  defp current_revision(document) do
    case status(document) do
      :unchanged ->
        :ok

      :changed ->
        {:error, "File changed on disk. Reload before saving; your canvas edits are still here."}

      :unavailable ->
        {:error, "File is missing or unreadable. Nothing was overwritten."}
    end
  end

  defp read_regular(path) do
    with {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, bytes} <- File.read(path) do
      {:ok, bytes}
    else
      {:ok, _stat} -> {:error, "Choose a regular file, not a directory or symbolic link."}
      {:error, reason} -> {:error, file_error(reason)}
    end
  end

  defp file_error(reason), do: "File error: #{:file.format_error(reason)}"
  defp digest(bytes), do: :crypto.hash(:sha256, bytes)

  defp preserve_fields(original, current, fields) do
    previous = Map.new(original || [], &{&1["id"], &1})

    Enum.map(current, fn object ->
      previous
      |> Map.get(object["id"], %{})
      |> Map.drop(fields)
      |> Map.merge(object)
    end)
  end

  defp preserve_paper(%{"paper" => paper} = source, original) when is_map(original) do
    Map.put(source, "paper", Map.merge(Map.drop(original, ~w(background grid)), paper))
  end

  defp preserve_paper(source, _original), do: source

  defp validate(%{"version" => version}) when version !== 1,
    do: {:error, "Unsupported canvas version. This app reads version 1 only."}

  defp validate(%{"version" => 1, "nodes" => nodes, "edges" => edges} = source)
       when is_list(nodes) and is_list(edges) do
    with :ok <- validate_each(nodes, &validate_node/1),
         :ok <- validate_each(edges, &validate_edge/1),
         :ok <- validate_paper(source["paper"]) do
      :ok
    end
  end

  defp validate(_source),
    do: {:error, "A canvas must be an object with version: 1, nodes: [], and edges: []."}

  defp validate_each(objects, validator) do
    Enum.reduce_while(objects, :ok, fn object, :ok ->
      case validator.(object) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_node(%{"id" => id, "type" => type, "data" => data} = node)
       when is_binary(id) and id != "" and type in ["shape", "shape-line"] and is_map(data) do
    cond do
      not Enum.all?(~w(x y width height), &is_number(node[&1])) ->
        {:error, "Node #{id} needs numeric x, y, width, and height."}

      node["width"] <= 0 or node["height"] <= 0 ->
        {:error, "Node #{id} needs positive dimensions."}

      not is_boolean(Map.get(node, "locked", false)) or node["parent"] != nil ->
        {:error, "Node #{id} has an invalid lock or parent. Groups are not supported yet."}

      type == "shape" ->
        validate_shape(id, data)

      true ->
        validate_line(id, data)
    end
  end

  defp validate_node(_node),
    do:
      {:error, "Each node needs a stable string id, type shape or shape-line, and a data object."}

  defp validate_shape(id, data) do
    text = Map.get(data, "text", "")

    if data["kind"] in ~w(rect ellipse diamond triangle text) and
         is_binary(text) and String.length(text) <= 2_000 do
      validate_style(id, data)
    else
      {:error, "Shape #{id} needs a supported kind and string text of at most 2000 characters."}
    end
  end

  defp validate_line(id, data) do
    if point?(data["from"]) and point?(data["to"]) do
      validate_style(id, data)
    else
      {:error, "Line #{id} needs from and to coordinate pairs."}
    end
  end

  defp point?([x, y]), do: is_number(x) and is_number(y)
  defp point?(_point), do: false

  defp validate_style(id, data) do
    options = %{
      "fill" => ~w(none ink gray blue green yellow red violet),
      "stroke" => ~w(none ink gray blue green yellow red violet),
      "width" => [1, 2, 4],
      "dash" => [true, false],
      "radius" => [0, 8],
      "size" => ~w(s m l),
      "align" => ~w(left center right),
      "arrow" => ~w(end both none)
    }

    cond do
      Enum.any?(options, fn {key, values} ->
        Map.has_key?(data, key) and data[key] not in values
      end) ->
        {:error, "Shape #{id} has an unsupported style value."}

      not is_number(Map.get(data, "rotation", 0)) ->
        {:error, "Shape #{id} needs a numeric rotation."}

      true ->
        :ok
    end
  end

  defp validate_edge(%{"id" => id, "source" => source, "target" => target} = edge)
       when is_binary(id) and id != "" and is_binary(source) and is_binary(target) do
    strings = ~w(source_handle target_handle label)

    if Enum.all?(strings, &(is_nil(edge[&1]) or is_binary(edge[&1]))) and
         is_boolean(Map.get(edge, "animated", false)) and is_map(Map.get(edge, "data", %{})) do
      :ok
    else
      {:error, "Connector #{id} has invalid labels, handles, animation, or data."}
    end
  end

  defp validate_edge(_edge),
    do: {:error, "Each connector needs stable string id, source, and target fields."}

  defp validate_paper(nil), do: :ok

  defp validate_paper(%{} = paper) do
    if Map.get(paper, "background", "dots") in ~w(dots lines cross none) do
      Hakushi.Paper.new(paper)
      :ok
    else
      {:error, "Unsupported paper background."}
    end
  end

  defp validate_paper(_paper), do: {:error, "Paper must be an object."}
end
