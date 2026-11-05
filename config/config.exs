import Config

if config_env() == :test do
  config :junit_formatter,
    report_dir: System.get_env("RESULT_DIR", "test-results/direct"),
    report_file: "unit.xml",
    automatic_create_dir?: true
end
