defmodule Exonerate do
  @moduledoc """
  An opinionated JSONSchema compiler for elixir.

  Currently supports JSONSchema drafts 4, 6, 7, 2019, and 2020.  *except:*

  - integer filters do not match exact integer floating point values.
  - multipleOf is not supported for the number type (don't worry, it IS supported
    for integers).  This is because Elixir does not support a floating point
    remainder guard, and also because it is impossible for a floating point to
    guarantee sane results (e.g. for IEEE Float64, `1.2 / 0.1 != 12`)
  - currently remoteref is not supported.

  For details, see:  http://json-schema.org

  Exonerate is automatically tested against the JSONSchema test suite.

  ## Usage

  Exonerate is 100% compile-time generated.  You should include Exonerate with
  the `runtime: false` option in `mix.exs`.

  ### In your module:

  ```
  defmodule MyModule do
    require Exonerate

    Exonerate.function_from_string(:def, :function_name, \"""
    {
      "type": "string"
    }
    \""")
  end
  ```

  The above module generates a function `MyModule.function_name/1` that takes an BEAM JSON term
  (`string | number | array | map | bool | nil`) and validates it based on the the JSONschema.  If
  the term validates, it produces `:ok`.  If the term fails to validate, it produces
  `{:error, keyword}`, where the key `:instance_location` and points to the error location in the passed
  parameter, the `:schema_pointers` points to the validation that failed, and `error_value` is the
  failing inner term.

  ## Error keywords

  The following error keywords conform to the JSONSchema spec
  (https://json-schema.org/draft/2020-12/json-schema-core.html#name-format):

  - `:absolute_keyword_location`: a JSON pointer to the keyword in the schema that failed.
  - `:instance_location`: a JSON pointer to the location in the instance that failed.
  - `:errors`: a list of errors generated when a combining filter fails to match.

  The following error keywords are not standard and are specific to Exonerate:

  - `:error_value`: the innermost term that failed to validate.
  - `:matches`: a list of JSON pointers to the keywords that matched a combining filter.
  - `:reason`: a string describing the error, when the failing filter can fail for nonobvious
    reasons.  For example `oneOf` will fail with the reason "no matches" when none of the
    child schemas match; but it will fail with the reason "multiple matches" when more than
    of the child schemas match.
  - `:required`: a list of object keys that were required but missing.
  - `:ref_trace`: a list of `$ref` keywords that were followed to get to the failing keyword.

  ## Options

  The following options are available:

  - `:metadata`: `true` to enable all metadata decorator functions or a list of
    atoms parameters to enable.  The following metadata are accessible by passing
    the corresponding atom to the generated function in lieu of a JSON term to
    validate.

    | JSONschema tag  | atom parameter |
    |-----------------|----------------|
    | $id or id       | `:id`          |
    | $schema         | `:schema_id`   |
    | default         | `:default`     |
    | examples        | `:examples`    |
    | description     | `:description` |
    | title           | `:title`       |
    | <entire schema> | `:schema`      |

  - `:format`: instructions for using (optional) format filters.  This should be
    either `true` or a keyword list.

    - `true`: shorthand for `[default: true]`
    - keywords:
      `<filter-spec>` may either be a module, which implies the existence of
      the `module.validate/1` function, `{module, function}` which implies
      the existence of `module.function/1`, or `{module, function, [extra-args]}`
      which implies the existence of `module.function/n` where the extra args
      are appended to the end of string to be validated.

      In all cases, the validation function is expected to emit `:ok` if the
      string validates, or `{:error, reason}`, if it does not.  `reason` should
      either be a string or `nil`.

      - `:at`: a list of `{<json pointer>, <filter-spec>}` tuples to apply
        format filters in specific locations in the schema.  This can be used
        to specify custom filters for non-default format types.  It can also be
        used to override default formatting.  `<json pointer>` should be a
        string which may be relative if no `"id"` or `"$id"` metadata are
        present in the parents of the location.  Otherwise, the pointer must
        the a uri of the nearest parent containing `"id"` or `"$id" metadata,
        with the relative pointer applied as the fragment of the uri.
      - `:type`: a list of `{<format-type>, <filter-spec>}` to apply across
        the schema whenever `<format-type>` is encountered.  This can be used
        to specify custom filters for non-default format types.  It can also
        be used to override default formatting.
      - `:default`: `true` to enable all default filters or a list of strings
        specifying the default format types to enable.  The following format
        types are available:
        - `"date-time"`: enables the default date-time filter for all
          `{"format": "date-time"}` contexts.  This uses Elixir's
          `NaiveDateTime.from_iso8601/1` parser.
        - `"date-time-utc"`: enables the default date-time-utc filter for all
          `{"format": "date-time-utc"}` contexts.  This uses Elixir's
          `DateTime.from_iso8601/1` parser, and requires the offset to be
          0 from UTC.
        - `"date-time-tz"`: enables the default date-time filter for all
          `{"format": "date-time-tz"}` context strings.  This uses Elixir's
          `DateTime.from_iso8601/1` parser, which requires an offset to
          be specified.
        - `"date"`: enables the default date filter for all `{"format": "date"}`
          context strings.  This uses Elixir's `Date.from_iso8601/1` parser.
        - `"time"`: enables the default time filter for all `{"format": "time"}`
          context strings.  This uses Elixir's `Time.from_iso8601/1` parser.
        - `"duration": enables the default duration filter for all
          `{"format": "duration"}` context strings.  This uses a custom ABNF
          filter that matches Appendix A of RFC 3339: https://www.rfc-editor.org/rfc/rfc3339.txt
        - `"ipv4"`: enables the default ipv4 filter for all `{"format": "ipv4"}`
          context strings.  This uses Erlang's `:inet.parse_ipv4strict_address/1`
          parser.
        - `"ipv6"`: enables the default ipv6 filter for all `{"format": "ipv6"}`
          context strings.  This uses Erlang's `:inet.parse_ipv6strict_address/1`
          parser.
        - `"uuid"`: enables the default uuid filter for all `{"format": "uuid"}`
          context strings.
        - `"email"`: enables the default email filter for all `{"format": "email"}`
          context strings.  This uses a custom ABNF filter that matches section 4.1.2
          of RFC 5322: https://www.rfc-editor.org/rfc/rfc5322.txt
        - `"idn-email"`: enables the default idn-email (i18n email address)
          filter for all `{"format": "idn-email"}` context strings.  This uses a
          custom ABNF filter that matches section 3.3 of RFC 6531:
          https://www.rfc-editor.org/rfc/rfc5322.txt
        - `"hostname"`: enables the default hostname filter for all
          `{"format": "hostname"}` context strings.  This uses a custom ABNF
          filter that matches section 2.1 of RFC 1123:
          https://www.rfc-editor.org/rfc/rfc1123.txt
        - `"idn-hostname"`: enables the default idn-hostname (i18n hostname)
          filter for all `{"format": "idn-hostname"}` context strings.

          Note that in order to use this filter, you must add the
          `:idna` library to your dependencies.
        - `"uri"`: enables the default uri filter for all `{"format": "uri"}`
          context strings.  This uses a custom ABNF filter that matches section
          3 of RFC 3986: https://www.rfc-editor.org/rfc/rfc3986.txt.  Note that
          a these uris must be absolute, i.e. they must contain a scheme, host,
          and path.
        - `"uri-reference"`: enables the default uri-reference filter for all
          `{"format": "uri-reference"}` context strings.  This uses a custom ABNF
          filter that matches section 3 of RFC 3986:
          https://www.rfc-editor.org/rfc/rfc3986.txt.  Note that a these uris
          may be relative, i.e. do not need to contain a scheme, host, and path.
        - `"iri"`: enables the default iri (i18n uri) filter for all
          `{"format": "iri"}` context strings.  This uses a custom ABNF filter
          that matches section 2.2 of RFC 3987: https://www.rfc-editor.org/rfc/rfc3987.txt.
          Note that a these iris must be absolute, i.e. they must contain a
          scheme, host, and path.
        - `"iri-reference"`: enables the default iri-reference (i18n uri) for all
          `{"format": "iri-reference"}` context strings.  This uses a custom ABNF
          filter that matches section 2.2 of RFC 3987: https://www.rfc-editor.org/rfc/rfc3987.txt.
          Note that a these iris may be relative, i.e. do not need to contain a
          scheme, host, and path.
        - `"uri-template"`: enables the default uri-template filter for all
          `{"format": "uri-template"}` context strings.  This uses a custom ABNF
          filter that matches section 2.3 of RFC 6570: https://www.rfc-editor.org/rfc/rfc6570.txt.
          Note that uri-templates are templated against iri-reference strings.
        - `"json-pointer"`: enables the default json-pointer filter for all
          `{"format": "json-pointer"}` context strings.  This uses a custom ABNF
          filter that matches section 3 of RFC 6901: https://www.rfc-editor.org/rfc/rfc6901.txt
        - `"relative-json-pointer"`: enables the default relative-json-pointer
          filter for all `{"format": "relative-json-pointer"}` context strings.
          This uses a custom ABNF filter that matches the followowing rfc proposal:
          https://datatracker.ietf.org/doc/html/draft-handrews-relative-json-pointer-01
        - `"regex"`: enables the default regex filter for all `{"format": "regex"}`
          context strings.  Note: this does not compile the regex, instead it
          uses a custom ABNF filter that matches the ECMA-262 standard:
          https://www.ecma-international.org/publications-and-standards/standards/ecma-262/

  - `:entrypoint`: a JSONpointer to the internal location inside of a json
    document where you would like to start the JSONschema.  This should be in
    JSONPointer form (not URI form).  See https://datatracker.ietf.org/doc/html/rfc6901
    for more information about JSONPointer

  - `:decoders`: a list of `{<mimetype>, <decoder>}` tuples.  `<encoding-type>`
    should be a string that matches the `content-type` of the schema. `<decoder>`
    should be one of the following:
    - `Jason` (default) for json parsing
    - `YamlElixir` for yaml parsing
    - `{module, function}` for custom parsing; the function should accept a
      string and return json term, raising if the string is not valid input
      for the decoder.

    Defaults to `[{"application/json", Jason}, {"application/yaml", YamlElixir}]`.
    Tuples specified in this option will override or add to the defaults.

  - `:draft`: specifies any special draft information.  Defaults to "2020",
    which is intercompatible with `"2019"`.  `"4"`, `"6"`, and `"7"` are also
    supported.  Note: Validation is NOT performed on the schema, so
    intermingling draft components is possible (but not recommended).  This overrides
    draft information provided in the schema

  ### remoteRef schema retrieval options

  - `:remote_fetch_adapter`: specifies the module to use for fetching remote
    resources.  This module must export a `fetch_remote_cache!/2` function which
    is passed a `t:URI.t/0` struct and returns `{<body>, <content-type>}` pair.
    content-type may be `nil`.  Defaults to `Exonerate.Remote`, which uses the
    `Req` library to perform the http request.

  - `:force_remote`: bypasses the manual prompt confirming if remote resources
    should be downoladed.  Use with caution!  Defaults to `false`.

  - `:cache`: if remote JSONs should be cached to the local filesystem.
    Defaults to `false`

  - `:cache_app`: specifies the otp app whose priv directory cached remote
    JSONs are stored. Defaults to `:exonerate`.

  - `:cache_path`: specifies the subdirectory of priv where cached remote JSONs
    are stored.  Defaults to `/`.

  - `:proxy`: a string proplist which describes string substitution of url
    resources for proxied remote content.

    #### Example

    ``` elixir
    [proxy: [{"https://my.remote.resource/", "http://localhost:4000"}]]
    ```
  """

  alias Exonerate.Cache
  alias Exonerate.Draft
  alias Exonerate.Tools
  alias Exonerate.Metadata
  alias Exonerate.Schema

  @doc """
  generates a series of functions that validates a provided JSONSchema.

  Note that the `schema` parameter must be a string literal.

  ### Extra options

  - `:content_type`: specifies the content-type of the provided schema string literal.
    Defaults to `"application/json"`.  This is used to determine which decoder to use
    to parse the schema.
  - `:mimetype_mapping`: a proplist of `{<extension>, <mimetype>}` tuples.
    This is used to determine the content-type of the schema if the file
    extension is unrecognized.  E.g. [{".html", "text/html"}].  The mappings
    {".json", "application/json"} and {".yaml", "application/yaml"} are not
    overrideable.
  """
  defmacro function_from_string(type, function_name, schema_ast, opts \\ []) do
    # expand literals (aliases) in ast.
    opts = opts
    |> Macro.expand_literals(__CALLER__)
    |> Keyword.put_new(:content_type, "application/json")
    |> Tools.set_decoders

    # prewalk the schema text
    root_pointer = Tools.entrypoint(opts)

    # TODO: also attempt to obtain this from the schema.
    draft = Keyword.get(opts, :draft, "2020-12")
    opts = Keyword.put(opts, :draft, draft)

    function_resource = to_string(%URI{scheme: "function", host: "#{function_name}", path: "/"})

    schema_string = Macro.expand(schema_ast, __CALLER__)

    build_code(__CALLER__, schema_string, type, function_name, function_resource, root_pointer, opts)
  end

  defp id_from(schema) when is_map(schema), do: schema["$id"] || schema["id"]
  defp id_from(_), do: nil

  @doc """
  generates a series of functions that validates a JSONschema in a file at
  the provided path.

  Note that the `path` parameter must be a `t:Path.t/0` value.

  ### Extra options

  - `:content_type`: specifies the content-type of the provided schema string
    literal. Defaults to `application/json` if the file extension is `.json`,
    and `application/yaml` if the file extension is `.yaml`  If `:content_type`
    is unspecified and the file extension is unrecognized, Exonerate will
    not be able to compile.
  - `:mimetype_mapping`: a proplist of `{<extension>, <mimetype>}` tuples.
    This is used to determine the content-type of the schema if the file
    extension is unrecognized.  E.g. [{".html", "text/html"}].  The mappings
    {".json", "application/json"} and {".yaml", "application/yaml"} are not
    overrideable.
  """
  defmacro function_from_file(type, function_name, path, opts \\ [])

  defmacro function_from_file(type, function_name, path, opts) do
    # expand literals (aliases) in ast.
    opts = opts
    |> Macro.expand_literals(__CALLER__)
    |> set_content_type(path)
    |> Tools.set_decoders

    # prewalk the schema text
    root_pointer = Tools.entrypoint(opts)

    # TODO: also attempt to obtain this from the schema.
    draft = Keyword.get(opts, :draft, "2020-12")
    opts = Keyword.put(opts, :draft, draft)

    function_resource = to_string(%URI{scheme: "file", host: "", path: Path.absname(path)})
    schema_string = File.read!(path)

    # set decoder options for the schema

    build_code(__CALLER__, schema_string, type, function_name, function_resource, root_pointer, opts)
  end

  defp build_code(caller, schema_string, type, function_name, function_resource, root_pointer, opts) do
    schema = Schema.ingest(schema_string, caller, function_resource, opts)

    opts = Draft.set_opts(opts, schema)

    resource =
      if id = id_from(schema) do
        resource = id
        Cache.put_schema(caller.module, resource, schema)
        resource
      else
        function_resource
      end

    schema_fn = Metadata.schema(schema_string, type, function_name, opts)

    call = Tools.call(resource, root_pointer, opts)

    Tools.maybe_dump(
      quote do
        require Exonerate.Metadata

        unquote(schema_fn)

        Exonerate.Metadata.functions(
          unquote(type),
          unquote(function_name),
          unquote(resource),
          unquote(root_pointer),
          unquote(opts)
        )

        unquote(type)(unquote(function_name)(data), do: unquote(call)(data, "/"))

        require Exonerate.Context
        Exonerate.Context.filter(unquote(resource), unquote(root_pointer), unquote(opts))
      end,
      opts
    )
  end

  defp set_content_type(opts, path) do
    Keyword.put_new_lazy(opts, :content_type, fn ->
      Tools.content_type_from_extension(path, opts)
    end)
  end
end
