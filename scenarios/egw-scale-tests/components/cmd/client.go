package cmd

import (
	"github.com/cilium/scaffolding/scenarios/egw-scale-tests/components/pkg"

	"github.com/spf13/cobra"
)

var (
	clientCfg = &pkg.ClientConfig{}

	clientCmd = &cobra.Command{
		Use: "client",
		Run: func(cmd *cobra.Command, args []string) {
			if err := pkg.RunClient(clientCfg); err != nil {
				panic(err)
			}
		},
	}
)

func init() {
	clientCmd.PersistentFlags().StringVar(
		&clientCfg.ExternalTargetAddr, "external-target-addr", "", "Address of external target to connect to. Needs to be of the format 'IP:Port'",
	)
	clientCmd.PersistentFlags().StringVar(
		&clientCfg.MetricsServerAddr, "metrics-server-addr", "", "Address of the metrics server to report results to. Needs to be of the format 'IP:Port'",
	)

	rootCmd.AddCommand(clientCmd)
}
