defmodule Reach.Smell.Source do
  @moduledoc false

  def cached_zipper(file) do
    key = {:reach_smell_zipper, file}

    case Process.get(key) do
      nil ->
        zipper =
          file
          |> File.read!()
          |> Sourceror.parse_string!()
          |> Sourceror.Zipper.zip()

        Process.put(key, zipper)
        zipper

      zipper ->
        zipper
    end
  end
end
