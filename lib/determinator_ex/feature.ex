defmodule DeterminatorEx.Feature do
  def call(feature, actor) do
    case determinate(feature, actor) do
      {:ok, v} -> {:ok, v}
      {:error, _} ->  {:error, false}
    end
  end

  defp determinate(feature, actor) do
    with {_, true} <- is_active?(feature),
         {:ok, nil} <- fixed_deterimation?(feature, actor),
         {:ok, actor_token} when is_binary(actor_token) <- actor_token(feature, actor),
         {:ok, indicator_token} <- indicator_token(feature.identifier, actor_token),
         {:ok, target_group} <- select_target_group(feature, actor),
         {:ok, true} <- in_target_group?(target_group, indicator_token),
         {:ok, nil} <- winning_variant?(feature),
         {:ok, possible_variant} <- maybe_select_variant(feature, indicator_token)
         do
          case possible_variant do
             nil -> {:ok, true}
              v -> {:ok, v}
          end
         end
  end

  defp is_active?(%{active: active}) do
    {:ok, active}
  end

  defp is_active?(_) do
    {:ok, false}
  end

  defp actor_token(%{bucket_type: "id"}, %{id: id}) when is_binary(id) do
    {:ok, id}
  end

  defp actor_token(%{bucket_type: "id"}, %{id: _}) do
    {:ok, false}
  end

  defp actor_token(%{bucket_type: "guid"}, %{guid: guid}) when is_binary(guid) do
    {:ok, guid}
  end

  defp actor_token(%{bucket_type: "fallback"}, actor) do
    case actor.id || actor.guid do
      nil -> {:error, "No valid actor token"}
      identifier -> {:ok, identifier}
    end
  end

  defp actor_token(%{bucket_type: "single"}, _) do
    {:ok, SecureRandom.hex(64)}
  end

  defp actor_token(_,_) do
    {:error, "No valid actor token set"}
  end

  defp indicator_token(identifier, actor_token) do
    hashed = :crypto.hash(:md5, "#{identifier},#{actor_token}") |> Base.encode16()
    chunked = for << chunk::size(32) <- hashed >>, do: <<chunk::size(32)>>
    token = chunked |> Enum.take(2) |> Enum.map(fn a -> a |> to_charlist() |> List.to_integer(16) end) |> List.to_tuple()
    {:ok, token}
  end

  defp maybe_select_variant(%{variants: variants}, indicator_token) when is_map(variants) do
    {_, variant_identifier} = indicator_token
    variants = Enum.to_list(variants) |> Enum.sort_by(fn {name, _} -> name end)
    sum_of_variants = Enum.reduce(variants, 0, fn {_, value}, acc -> value + acc end)
    scale_factor = 65_535 / sum_of_variants
    {selected, _} = Enum.reduce_while(variants, {nil, 0}, fn {variant_name, variant_weight}, {_, upper_bound} ->
      new_upper = upper_bound + scale_factor * variant_weight
      if variant_identifier <= new_upper do
        {:halt, {variant_name, new_upper}}
      else
        {:cont, {variant_name, new_upper}}
      end
    end)
    {:ok, Atom.to_string(selected)}
  end

  defp maybe_select_variant(_,_) do
    {:ok, nil}
  end

  defp select_target_group(feature, actor) do
    selected = feature.target_groups
    |> Enum.flat_map(fn group ->
      if (group.rollout >= 1 && group.rollout <= 65_536) && matches_constraints(group.constraints, actor.properties) do
        [group]
      else
        []
      end
    end)
    {:ok, List.first(selected)}
  end

  defp winning_variant?(%{winning_variant: winner}) do
    {:ok, winner}
  end

  defp winning_variant?(_) do
    {:ok, nil}
  end

  defp in_target_group?(nil, _) do
    {:ok, false}
  end

  defp in_target_group?(target_group, indicators) do
    {actor_indicator, _} = indicators
    {:ok, (actor_indicator < target_group.rollout)}
  end

  defp fixed_deterimation?(%{fixed_determinations: fixed_determinations}, %{properties: properties}) do
    Enum.find(fixed_determinations, fn fixed ->
      matches_constraints(fixed.constraints, properties)
    end)
    |> case do
       nil -> {:ok, nil}
       %{variant: v, feature_on: true} -> {:ok, v || true}
       %{feature_on: on} -> {:ok, on}
    end
  end

  defp fixed_deterimation?(_, _) do
    {:ok, nil}
  end


  defp matches_constraints(properties, _) when properties == %{} do
    true
  end

  defp matches_constraints(_, constraints) when constraints == %{} do
    true
  end

  defp matches_constraints(properties, constraints) do
    Enum.all?(properties, fn {k, v} ->
      case k do
        :app_version ->
          match_app_versions(v, Map.get(constraints, k, Map.get(constraints, :"request.app_version", nil)))
        :"request.app_version" ->
          match_app_versions(v, Map.get(constraints, k,  Map.get(constraints, :app_version, nil)))
        _ -> matches_contraints(v, Map.get(constraints, k, nil))
      end
    end)
  end

  defp matches_contraints(a, b) do
    !MapSet.disjoint?(
        MapSet.new(norm_constraints(a)),
        MapSet.new(norm_constraints(b))
      )
  end

  defp match_app_versions(requirements, versions) do
    Enum.any?(versions, fn version ->
      Enum.all?(requirements, fn requirement ->
        try do
          Version.match?(version, requirement)
        rescue
          _ -> false
        end
      end)
    end)
  end

  defp norm_constraints(constraints) do
    constraints
    |> List.wrap()
    |> Enum.map(fn a -> to_string(a) end)
  end
end
