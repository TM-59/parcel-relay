# Credo in strict mode over every Elixir file written in this repository; no check is disabled.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: [
          "mix.exs",
          ".formatter.exs",
          ".credo.exs",
          "lib/",
          "test/",
          "config/",
          "scripts/"
        ],
        excluded: []
      }
    }
  ]
}
