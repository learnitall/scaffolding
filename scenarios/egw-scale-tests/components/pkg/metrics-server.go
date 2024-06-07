package pkg

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type MetricsServerConfig struct {
	ListenPort int
}

var (
	failedRequestsCounter = promauto.NewCounter(prometheus.CounterOpts{
		Name: "egw_scale_test_failed_requests_total",
		Help: "The total number of failed requests a client made when trying to access the external target",
	})

	masqueradeDelaySummary = promauto.NewSummary(prometheus.SummaryOpts{
		Name:   "egw_scale_test_masquerade_delay_seconds",
		Help:   "The number of seconds between a client pod starting and hitting the external target",
		MaxAge: time.Hour,
		Objectives: map[float64]float64{
			0.5:  0.01,
			0.9:  0.01,
			0.95: 0.01,
			0.99: 0.001,
		},
	})
)

func getResultHandler(logger *slog.Logger) func(http.ResponseWriter, *http.Request) {
	resultHandler := func(w http.ResponseWriter, r *http.Request) {
		l := logger.With("remote-addr", r.RemoteAddr)

		if r.Method != http.MethodPost {
			l.Warn("Recieved non-Post request")
			w.WriteHeader(http.StatusBadRequest)

			return
		}

		var bodyBuffer bytes.Buffer

		_, err := io.Copy(&bodyBuffer, r.Body)
		if err != nil {
			l.Error("Unexpected error while reading request body", "err", err)
			w.WriteHeader(http.StatusInternalServerError)

			return
		}

		body := bodyBuffer.Bytes()
		result := Result{}

		if err := json.Unmarshal(body, &result); err != nil {
			l.Error("Unexpected error while unmarshaling request body", "err", err, "body", body)
			w.WriteHeader(http.StatusBadRequest)

			return
		}

		w.WriteHeader(http.StatusAccepted)

		failedRequestsCounter.Add(float64(result.NumFailedRequests))
		masqueradeDelaySummary.Observe(result.MasqueradeDelay)

		l.Info("Received result from client", "result", result)
	}

	return resultHandler
}

func RunMetricsServer(cfg *MetricsServerConfig) error {
	logger := NewLogger("metrics-server")

	http.Handle("/metrics", promhttp.Handler())
	http.HandleFunc("/result", getResultHandler(logger))

	listenAddr := net.JoinHostPort(
		"0.0.0.0",
		strconv.FormatInt(int64(cfg.ListenPort), 10),
	)

	logger.Info("Listening for http requests", "listen-addr", listenAddr)
	return http.ListenAndServe(listenAddr, nil)
}
