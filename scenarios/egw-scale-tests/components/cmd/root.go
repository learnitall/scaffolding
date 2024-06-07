package cmd

import "github.com/spf13/cobra"

var (
	rootCmd = &cobra.Command{
		Use: "egw-perf-test",
	}
)

func init() {
	rootCmd.Root().CompletionOptions.DisableDefaultCmd = true
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		panic(err)
	}
}
