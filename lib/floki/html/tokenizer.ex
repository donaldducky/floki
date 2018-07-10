defmodule Floki.HTML.Tokenizer do
  @lower_ASCII_letters Enum.map(?a..?z, fn l -> <<l::utf8>> end)
  @upper_ASCII_letters Enum.map(?a..?z, fn l -> <<l::utf8>> end)
  @all_ASCII_letters @lower_ASCII_letters ++ @upper_ASCII_letters
  @space_chars ["\t", "\n", "\f", "\s"]
  # It represents the state of tokenization.
  defmodule State do
    defstruct current: nil,
              return_state: nil,
              token: nil,
              tokens: [],
              buffer: "",
              last_start_tag: nil,
              open_tags: [],
              line: 1,
              column: 1
  end

  def tokenize(html) do
    tokenize(html, %State{current: :data})
  end

  defp tokenize(_, %State{tokens: [{:eof, _, _} | tokens]}), do: Enum.reverse(tokens)

  # § tokenizer-data-state

  defp tokenize(<<"&", html::binary>>, s = %State{current: :data}) do
    tokenize(html, %{s | return_state: :data, current: :char_ref, column: s.column + 1})
  end

  defp tokenize(<<"<", html::binary>>, s = %State{current: :data}) do
    tokenize(html, %{s | current: :tag_open, column: s.column + 1})
  end

  defp tokenize(<<"\0", html::binary>>, s = %State{current: :data}) do
    tokenize(html, %{s | tokens: [{:char, "\0"} | s.tokens]})
  end

  defp tokenize(html = "", s = %State{current: :data}) do
    tokenize(html, %{s | tokens: [{:eof, s.column, s.line} | s.tokens]})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :data}) do
    tokenize(html, %{s | tokens: [{:char, c} | s.tokens]})
  end

  # § tokenizer-rcdata-state

  defp tokenize(<<"&", html::binary>>, s = %State{current: :rcdata}) do
    tokenize(html, %{s | return_state: :rcdata, current: :char_ref, column: s.column + 1})
  end

  defp tokenize(<<"<", html::binary>>, s = %State{current: :rcdata}) do
    tokenize(html, %{s | current: :rcdata_less_than_sign, column: s.column + 1})
  end

  defp tokenize(<<"\0", html::binary>>, s = %State{current: :rcdata}) do
    tokenize(html, %{s | tokens: [{:char, "\uFFFD"} | s.tokens]})
  end

  defp tokenize(html = "", s = %State{current: :rcdata}) do
    tokenize(html, %{s | tokens: [{:eof, s.column, s.line} | s.tokens]})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :rcdata}) do
    tokenize(html, %{s | tokens: [{:char, c} | s.tokens], column: s.column + 1})
  end

  # § tokenizer-rawtext-state

  defp tokenize(<<"<", html::binary>>, s = %State{current: :rawtext}) do
    tokenize(html, %{s | current: :rawtext_less_than_sign})
  end

  defp tokenize(<<"\0", html::binary>>, s = %State{current: :rawtext}) do
    tokenize(html, %{s | tokens: [{:char, "\uFFFD"} | s.tokens]})
  end

  defp tokenize(html = "", s = %State{current: :rawtext}) do
    tokenize(html, %{s | tokens: [{:eof, s.column, s.line} | s.tokens]})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :rawtext}) do
    tokenize(html, %{s | tokens: [{:char, c} | s.tokens], column: s.column + 1})
  end

  # § tokenizer-script-data-state

  defp tokenize(<<"<", html::binary>>, s = %State{current: :script_data}) do
    tokenize(html, %{s | current: :script_data_less_than_sign})
  end

  defp tokenize(<<"\0", html::binary>>, s = %State{current: :script_data}) do
    tokenize(html, %{s | tokens: [{:char, "\uFFFD"} | s.tokens]})
  end

  defp tokenize(html = "", s = %State{current: :script_data}) do
    tokenize(html, %{s | tokens: [{:eof, s.column, s.line} | s.tokens]})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :script_data}) do
    tokenize(html, %{s | tokens: [{:char, c} | s.tokens], column: s.column + 1})
  end

  # § tokenizer-plaintext-state

  defp tokenize(<<"\0", html::binary>>, s = %State{current: :plaintext}) do
    tokenize(html, %{s | tokens: [{:char, "\uFFFD"} | s.tokens]})
  end

  defp tokenize(html = "", s = %State{current: :plaintext}) do
    tokenize(html, %{s | tokens: [{:eof, s.column, s.line} | s.tokens]})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :plaintext}) do
    tokenize(html, %{s | tokens: [{:char, c} | s.tokens], column: s.column + 1})
  end

  # § tokenizer-tag-open-state

  defp tokenize(<<"!", html::binary>>, s = %State{current: :tag_open}) do
    tokenize(html, %{s | current: :markup_declaration_open, column: s.column + 1})
  end

  defp tokenize(<<"/", html::binary>>, s = %State{current: :tag_open}) do
    tokenize(html, %{s | current: :end_tag_open, column: s.column + 1})
  end

  defp tokenize(html = <<c::bytes-size(1), _rest::binary>>, s = %State{current: :tag_open})
       when c in @all_ASCII_letters do
    token = {:start_tag, "", s.column, s.line}

    tokenize(html, %{s | token: token, current: :tag_name})
  end

  defp tokenize(html = <<"?", _rest::binary>>, s = %State{current: :tag_open}) do
    token = {:comment, "", s.column, s.line}

    tokenize(html, %{s | token: token, current: :bogus_comment})
  end

  defp tokenize(html, s = %State{current: :tag_open}) do
    less_than_sign = {:char, "\u003C"}

    tokenize(html, %{s | token: nil, tokens: [less_than_sign | s.tokens], current: :data})
  end

  # § tokenizer-end-tag-open-state

  defp tokenize(html = <<c::bytes-size(1), _rest::binary>>, s = %State{current: :end_tag_open})
       when c in @all_ASCII_letters do
    token = {:end_tag, "", s.column, s.line}

    tokenize(html, %{s | token: token, current: :tag_name})
  end

  defp tokenize(<<">", html::binary>>, s = %State{current: :end_tag_open}) do
    tokenize(html, %{s | token: nil, current: :data})
  end

  defp tokenize(html = "", s = %State{current: :end_tag_open}) do
    eof = {:eof, s.column, s.line}
    solidus = {:char, "\u002F"}
    less_than_sign = {:char, "\u003C"}

    tokens = [eof, solidus, less_than_sign | s.tokens]
    tokenize(html, %{s | token: nil, tokens: tokens, current: :data})
  end

  defp tokenize(html, s = %State{current: :end_tag_open}) do
    token = {:comment, "", s.column, s.line}

    tokenize(html, %{s | token: token, current: :bogus_comment})
  end

  # § tokenizer-tag-name-state

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :tag_name})
       when c in @space_chars do
    line = line_number(c, s.line)
    tokenize(html, %{s | current: :before_attribute_name, column: s.column + 1, line: line})
  end

  defp tokenize(<<"/", html::binary>>, s = %State{current: :tag_name}) do
    tokenize(html, %{s | current: :self_closing_start_tag, column: s.column + 1})
  end

  defp tokenize(<<">", html::binary>>, s = %State{current: :tag_name}) do
    tokenize(html, %{
      s
      | current: :data,
        last_start_tag: s.token,
        tokens: [s.token | s.tokens],
        token: nil,
        column: s.column + 1
    })
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :tag_name})
       when c in @upper_ASCII_letters do
    {:start_tag, tag_name, col, line} = s.token
    new_token = {:start_tag, tag_name <> String.downcase(c), col + 1, line}

    tokenize(html, %{s | token: new_token, column: col + 1})
  end

  defp tokenize(<<"\0", html::binary>>, s = %State{current: :tag_name}) do
    {:start_tag, tag_name, col, line} = s.token

    tokenize(html, %{
      s
      | token: {:start_tag, tag_name <> "\uFFFD", col + 1, line},
        column: col + 1
    })
  end

  defp tokenize(html = "", s = %State{current: :tag_name}) do
    tokenize(html, %{s | token: nil, tokens: [{:eof, s.column, s.line} | s.tokens]})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :tag_name}) do
    {:start_tag, tag_name, col, line} = s.token
    new_token = {:start_tag, tag_name <> c, col + 1, line}

    tokenize(html, %{s | token: new_token, column: col + 1})
  end

  # § tokenizer-rcdata-less-than-sign-state

  defp tokenize(<<"/", html::binary>>, s = %State{current: :rcdata_less_than_sign}) do
    tokenize(html, %{s | buffer: "", current: :rcdata_end_tag_open, column: s.column + 1})
  end

  defp tokenize(html, s = %State{current: :rcdata_less_than_sign}) do
    less_than_sign = {:char, "\u003C"}

    tokenize(html, %{s | token: nil, tokens: [less_than_sign | s.tokens], current: :rcdata})
  end

  # § tokenizer-rcdata-end-tag-open-state

  defp tokenize(
         html = <<c::bytes-size(1), _rest::binary>>,
         s = %State{current: :rcdata_end_tag_open}
       )
       when c in @all_ASCII_letters do
    token = {:end_tag, "", s.column, s.line}
    tokenize(html, %{s | token: token, current: :rcdata_end_tag_name})
  end

  defp tokenize(html, s = %State{current: :rcdata_end_tag_open}) do
    solidus = {:char, "\u002F"}
    less_than_sign = {:char, "\u003C"}

    tokens = [solidus, less_than_sign | s.tokens]
    tokenize(html, %{s | tokens: tokens, current: :rcdata})
  end

  # § tokenizer-rcdata-end-tag-name-state

  defp tokenize(
         html = <<c::bytes-size(1), rest::binary>>,
         s = %State{current: :rcdata_end_tag_name}
       )
       when c in @space_chars do
    line = line_number(c, s.line)

    if appropriate_tag?(s) do
      tokenize(rest, %{s | current: :before_attribute_name, column: s.column + 1, line: line})
    else
      tokenize(html, %{
        s
        | tokens: tokens_for_inappropriate_end_tag(s),
          buffer: "",
          current: :rcdata
      })
    end
  end

  defp tokenize(html = <<"/", rest::binary>>, s = %State{current: :rcdata_end_tag_name}) do
    if appropriate_tag?(s) do
      tokenize(rest, %{s | current: :self_closing_start_tag, column: s.column + 1})
    else
      tokenize(html, %{
        s
        | tokens: tokens_for_inappropriate_end_tag(s),
          buffer: "",
          current: :rcdata
      })
    end
  end

  defp tokenize(html = <<">", rest::binary>>, s = %State{current: :rcdata_end_tag_name}) do
    if appropriate_tag?(s) do
      tokenize(rest, %{
        s
        | current: :data,
          token: nil,
          tokens: [s.token | s.tokens],
          column: s.column + 1
      })
    else
      tokenize(html, %{
        s
        | tokens: tokens_for_inappropriate_end_tag(s),
          buffer: "",
          current: :rcdata
      })
    end
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :rcdata_end_tag_name})
       when c in @upper_ASCII_letters do
    {:end_tag, end_tag, col, line} = s.token
    downcase_char = String.downcase(c)
    new_token = {:end_tag, end_tag <> downcase_char, col + 1, line}

    tokenize(html, %{s | token: new_token, buffer: s.buffer <> c})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :rcdata_end_tag_name})
       when c in @lower_ASCII_letters do
    {:end_tag, end_tag, col, line} = s.token
    new_token = {:end_tag, end_tag <> c, col + 1, line}

    tokenize(html, %{s | token: new_token, buffer: s.buffer <> c})
  end

  defp tokenize(html, s = %State{current: :rcdata_end_tag_name}) do
    tokenize(html, %{
      s
      | tokens: tokens_for_inappropriate_end_tag(s),
        buffer: "",
        current: :rcdata
    })
  end

  # TODO
  # § tokenizer-rawtext-less-than-sign-state

  defp tokenize(<<"!", html::binary>>, s = %State{current: :markup_declaration_open}) do
    case html do
      <<"--", rest::binary>> ->
        token = {:comment, "", s.line, s.column}

        tokenize(
          rest,
          %{s | current: :comment_start, token: token, column: s.column + 3}
        )

      <<"[", cdata::bytes-size(5), "]", rest::binary>> ->
        if String.match?(cdata, ~r/cdata/i) do
          # TODO: fix cdata state
          tokenize(
            rest,
            s
          )
        end

      <<doctype::bytes-size(7), rest::binary>> when doctype in ["doctype", "DOCTYPE"] ->
        token = {:doctype, nil, nil, nil, false, s.line, s.column}

        tokenize(
          rest,
          %{s | current: :doctype, token: token, column: s.column + 7}
        )

      _ ->
        tokenize(html, s)
    end
  end

  defp tokenize(<<"-", html::binary>>, s = %State{current: :comment_start}) do
    tokenize(html, %{s | current: :comment_start_dash, column: s.column + 1})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :comment_start}) do
    {:comment, comment, _, _} = s.token
    new_token = {:comment, comment <> c, s.line, s.column}

    tokenize(
      html,
      %{s | current: :comment, token: new_token, column: s.column + 1}
    )
  end

  defp tokenize(<<"-", html::binary>>, s = %State{current: :comment}) do
    tokenize(html, %{s | current: :comment_end_dash, column: s.column + 1})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :comment}) do
    {:comment, comment, l, cl} = s.token
    new_token = {:comment, comment <> c, l, cl}

    tokenize(
      html,
      %{s | current: :comment, token: new_token, column: s.column + 1}
    )
  end

  defp tokenize(<<"-", html::binary>>, s = %State{current: :comment_start_dash}) do
    tokenize(html, %{s | current: :comment_end, column: s.column + 1})
  end

  defp tokenize(<<"-", html::binary>>, s = %State{current: :comment_end_dash}) do
    tokenize(html, %{s | current: :comment_end, column: s.column + 1})
  end

  defp tokenize(<<">", html::binary>>, s = %State{current: :comment_end}) do
    tokenize(
      html,
      %{s | current: :data, tokens: [s.token | s.tokens], token: nil, column: s.column + 1}
    )
  end

  defp tokenize(html = "", s = %State{current: :comment_end}) do
    tokenize(
      html,
      %{
        s
        | current: :data,
          tokens: [{:eof, s.column, s.line} | [s.token | s.tokens]],
          token: nil,
          column: s.column + 1
      }
    )
  end

  defp tokenize(<<"!", html::binary>>, s = %State{current: :comment_end}) do
    tokenize(html, %{s | current: :comment_end_bang})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :doctype})
       when c in @space_chars do
    line = line_number(c, s.line)
    tokenize(html, %{s | current: :before_doctype_name, column: s.column + 1, line: line})
  end

  # This is a case of error, when there is no token left. It shouldn't be executed because
  # of the base function that stops the recursion.
  # TODO: implement me, since the problem describe was solved.
  # defp tokenize("", s = %State{current: :doctype}) do
  # end

  defp tokenize(html, s = %State{current: :doctype}) do
    tokenize(html, %{s | current: :before_doctype_name})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :before_doctype_name})
       when c in @space_chars do
    line = line_number(c, s.line)
    tokenize(html, %{s | current: :before_doctype_name, column: s.column + 1, line: line})
  end

  defp tokenize(<<">", html::binary>>, s = %State{current: :before_doctype_name}) do
    token = {:doctype, nil, nil, nil, true, s.line, s.column}

    tokenize(html, %{
      s
      | current: :data,
        tokens: [token | s.tokens],
        token: nil,
        column: s.column + 1
    })
  end

  defp tokenize(<<"\0", html::binary>>, s = %State{current: :before_doctype_name}) do
    token = {:doctype, "\uFFFD", nil, nil, true, s.line, s.column}
    tokenize(html, %{s | current: :doctype_name, token: token, column: s.column + 1})
  end

  defp tokenize("", s = %State{current: :before_doctype_name}) do
    token = {:doctype, nil, nil, nil, true, s.line, s.column}

    tokenize("", %{
      s
      | tokens: [{:eof, s.line, s.column} | [token | s.tokens]],
        token: nil,
        column: s.column + 1
    })
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :before_doctype_name}) do
    token = {:doctype, String.downcase(c), nil, nil, false, s.line, s.column + 1}
    tokenize(html, %{s | current: :doctype_name, token: token, column: s.column + 1})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :doctype_name})
       when c in @space_chars do
    line = line_number(c, s.line)
    tokenize(html, %{s | current: :after_doctype_name, column: s.column + 1, line: line})
  end

  defp tokenize(<<">", html::binary>>, s = %State{current: :doctype_name}) do
    # TODO: get column from tuple instead
    token = put_elem(s.token, 6, s.column + 1)

    tokenize(html, %{
      s
      | current: :data,
        tokens: [token | s.tokens],
        token: nil,
        column: s.column + 1
    })
  end

  defp tokenize(<<"\0", html::binary>>, s = %State{current: :doctype_name}) do
    {:doctype, name, _, _, _, _, column} = s.token
    new_token = put_elem(s.token, 1, name <> "\uFFFD") |> put_elem(6, column + 1)
    tokenize(html, %{s | current: :doctype_name, token: new_token, column: s.column + 1})
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :doctype_name}) do
    {:doctype, name, _, _, _, _, column} = s.token
    new_token = put_elem(s.token, 1, name <> String.downcase(c)) |> put_elem(6, column + 1)
    tokenize(html, %{s | current: :doctype_name, token: new_token, column: s.column + 1})
  end

  defp tokenize("", s = %State{current: :doctype_name}) do
    token = put_elem(s.token, 4, true)

    tokenize("", %{
      s
      | tokens: [{:eof, s.line, s.column} | [token | s.tokens]],
        token: nil,
        column: s.column + 1
    })
  end

  defp tokenize(<<c::bytes-size(1), html::binary>>, s = %State{current: :after_doctype_name})
       when c in @space_chars do
    line = line_number(c, s.line)
    tokenize(html, %{s | current: :after_doctype_name, column: s.column + 1, line: line})
  end

  defp tokenize(<<">", html::binary>>, s = %State{current: :after_doctype_name}) do
    # TODO: get column from tuple instead
    token = put_elem(s.token, 6, s.column + 1)

    tokenize(html, %{
      s
      | current: :data,
        tokens: [token | s.tokens],
        token: nil,
        column: s.column + 1
    })
  end

  defp tokenize("", s = %State{current: :after_doctype_name}) do
    token = put_elem(s.token, 4, true)

    tokenize("", %{
      s
      | tokens: [{:eof, s.line, s.column} | [token | s.tokens]],
        token: nil,
        column: s.column + 1
    })
  end

  defp tokenize(<<public::bytes-size(6), html::binary>>, s = %State{current: :after_doctype_name})
       when public in ["public", "PUBLIC"] do
    tokenize(html, %{s | current: :after_doctype_public_keyword, column: s.column + 6})
  end

  defp line_number("\n", current_line), do: current_line + 1
  defp line_number(_, current_line), do: current_line

  defp appropriate_tag?(state) do
    with {:start_tag, start_tag_name, _, _} <- state.last_start_tag,
         {:end_tag, end_tag_name, _, _} <- state.token,
         true <- start_tag_name == end_tag_name do
      true
    else
      _ -> false
    end
  end

  defp tokens_for_inappropriate_end_tag(state) do
    solidus = {:char, "\u002F"}
    less_than_sign = {:char, "\u003C"}
    buffer_chars = String.codepoints(state.buffer) |> Enum.map(&{:char, &1})

    tokens = [solidus, less_than_sign | state.tokens]
    Enum.reduce(buffer_chars, tokens, fn char, acc -> [char | acc] end)
  end
end
