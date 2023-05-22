defimpl Scrivener.Paginater, for: Ecto.Query do
  import Ecto.Query

  alias Scrivener.{Config, Page}

  @moduledoc false

  @spec paginate(Ecto.Query.t(), Scrivener.Config.t()) :: Scrivener.Page.t()
  def paginate(query, %Config{
        page_size: page_size,
        page_number: page_number,
        module: repo,
        caller: caller,
        options: options
      }) do
    total_entries =
      Keyword.get_lazy(options, :total_entries, fn ->
        total_entries(query, repo, caller, options)
      end)

    total_pages = total_pages(total_entries, page_size, page_number)
    allow_overflow_page_number = Keyword.get(options, :allow_overflow_page_number, total_entries == -1)
    page_number = calc_pages(allow_overflow_page_number, total_pages, page_number)
    %Page{
      page_size: page_size,
      page_number: page_number,
      entries: entries(query, repo, page_number, total_pages, page_size, caller, options),
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  defp calc_pages(true = _overflow, _total_pages, page_number), do: page_number
  defp calc_pages(_no_overflow, total_pages, page_number), do: min(total_pages, page_number)

  defp entries(_, _, page_number, total_pages, _, _, _) when page_number > total_pages and total_pages != -1, do: []

  defp entries(query, repo, page_number, _, page_size, caller, options) do
    offset = Keyword.get_lazy(options, :offset, fn -> page_size * (page_number - 1) end)
    prefix = options[:prefix]

    query
    |> offset(^offset)
    |> limit(^page_size)
    |> all(repo, caller, prefix)
  end

  defp total_entries(query, repo, caller, options) do
    prefix = options[:prefix]
    disable_count = options[:disable_count] || false
    query =
      query
      |> exclude(:preload)
      |> exclude(:order_by)
      |> aggregate(disable_count)

    if query != -1 do
      one(query, repo, caller, prefix) || 0
    else
      -1
    end
  end

  defp aggregate(%{distinct: %{expr: expr}} = query, disable_count) when expr == true or is_list(expr) do
    query
    |> exclude(:select)
    |> count(disable_count)
  end

  defp aggregate(
         %{
           group_bys: [
             %Ecto.Query.QueryExpr{
               expr: [
                 {{:., [], [{:&, [], [source_index]}, field]}, [], []} | _
               ]
             }
             | _
           ]
         } = query,
         disable_count
       ) do
    query
    |> exclude(:select)
    |> select([{x, source_index}], struct(x, ^[field]))
    |> count(disable_count)
  end

  defp aggregate(query, disable_count) do
    if disable_count do
      -1
    else
      query
      |> exclude(:select)
      |> select(count("*"))
    end
  end

  defp count(query, disable_count) do
    if disable_count do
      -1
    else
      query
      |> subquery
      |> select(count("*"))
    end
  end

  defp total_pages(-1, _page_size, page_number), do: page_number
  defp total_pages(0, _page_size, _page_number), do: 1

  defp total_pages(total_entries, page_size, _page_number) do
    (total_entries / page_size) |> Float.ceil() |> round
  end

  defp all(query, repo, caller, nil) do
    repo.all(query, caller: caller)
  end

  defp all(query, repo, caller, prefix) do
    repo.all(query, caller: caller, prefix: prefix)
  end

  defp one(query, repo, caller, nil) do
    repo.one(query, caller: caller)
  end

  defp one(query, repo, caller, prefix) do
    repo.one(query, caller: caller, prefix: prefix)
  end
end
