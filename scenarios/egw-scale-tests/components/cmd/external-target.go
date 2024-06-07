package cmd

import (
	"github.com/cilium/scaffolding/scenarios/egw-scale-tests/components/pkg"

	"github.com/spf13/cobra"
)

var (
	externalTargetCfg = &pkg.ExternalTargetConfig{}

	externalTargetCmd = &cobra.Command{
		Use: "external-target",
		Run: func(cmd *cobra.Command, args []string) {
			if err := pkg.RunExternalTarget(externalTargetCfg); err != nil {
				panic(err)
			}
		},
	}
)

func init() {
	externalTargetCmd.PersistentFlags().StringVar(
		&externalTargetCfg.AllowedCIDRString, "allowed-cidr", "", "Only respond to clients from the given CIDR",
	)
	externalTargetCmd.PersistentFlags().IntVar(
		&externalTargetCfg.ListenPort, "listen-port", 1337, "Port to listen for incomming connections on",
	)

	rootCmd.AddCommand(externalTargetCmd)
}
