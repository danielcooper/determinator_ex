defmodule DeterminatorExTest do
  use ExUnit.Case
  doctest DeterminatorEx

  describe "call/2" do
    test "matches standard tests" do
      "./test/standard_cases/examples.json"
      |> File.read!()
      |> Poison.decode!(%{keys: :atoms})
      |> get_in([Access.all(), :examples])
      |> List.flatten()
      |> Enum.each(fn example ->
        expected_determination =
          case example do
            %{error: _, returns: returns} -> {:error, returns}
            %{error: true} -> {:error, false}
            %{returns: returns} -> {:ok, returns}
          end

        {feature, properties} = build_arguments(example)
        determination = DeterminatorEx.Feature.call(feature, properties)
        assert(determination == expected_determination, example.why)
      end)
    end
  end

  def build_arguments(example) do
    feature =
      "./test/standard_cases/#{example.feature}"
      |> File.read!()
      |> Poison.decode!(%{keys: :atoms})

    {feature, Map.take(example, [:id, :guid, :properties])}
  end
end
