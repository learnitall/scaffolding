package cmd

import (
	"github.com/cilium/scaffolding/scenarios/egw-scale-tests/components/pkg"

	"github.com/spf13/cobra"
)

var (
	metricsServerCfg = &pkg.MetricsServerConfig{}

	metricsServerCmd = &cobra.Command{
		Use: "metrics-server",
		Run: func(cmd *cobra.Command, args []string) {
			if err := pkg.RunMetricsServer(metricsServerCfg); err != nil {
				panic(err)
			}
		},
	}
)

func init() {
	metricsServerCmd.PersistentFlags().IntVar(
		&metricsServerCfg.ListenPort, "listen-port", 2112, "Port to listen for incomming connections on",
	)

	rootCmd.AddCommand(metricsServerCmd)
}
