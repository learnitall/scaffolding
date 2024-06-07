package pkg

import (
	"io"
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

type ClientConfig struct {
	ExternalTargetAddr string
	MetricsServerAddr  string
}

func RunClient(cfg *ClientConfig) error {
	podName := os.Getenv("POD_NAME")
	if podName == "" {
		return errors.New("env variable POD_NAME is not set")
	}

	podNamespace := os.Getenv("POD_NAMESPACE")
	if podNamespace == "" {
		return errors.New("env variable POD_NAMESPACE is not set")
	}

	logger := NewLogger("client").With("external-target", cfg.ExternalTargetAddr)

	numMissed := 0
	d := net.Dialer{
		Timeout: time.Millisecond * 50,
	}

	var err error
	var conn net.Conn
	var endTime time.Time

	startTime := time.Now()

	for {
		if numMissed > 0 {
			time.Sleep(50 * time.Millisecond)
		}

		conn, err = d.Dial("tcp4", cfg.ExternalTargetAddr)
		endTime = time.Now()

		if err != nil {
			return err
		}

		reply, err := bufio.NewReader(conn).ReadString('\n')
		if err != nil && !errors.Is(err, io.EOF) {
			conn.Close()

			return err
		}

		if reply != "pong\n" {
			numMissed += 1
			logger.Debug("Received incorrect reply", "reply", reply)
			conn.Close()

			continue
		}

		logger.Info("Successfully connected to external target", "num-missed", numMissed)
		conn.Close()
		break
	}

	result := Result{
		ClientID:          strings.Join([]string{podNamespace, podName}, "/"),
		NumFailedRequests: numMissed,
		MasqueradeDelay:   endTime.Sub(startTime).Seconds(),
	}

	resultBytes, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("unable to marshal result to json: %v", err)
	}

	bodyBuffer := bytes.NewBuffer(resultBytes)

	logger.Info(
		"Sending result to metrics server",
		"metrics-server-addr", cfg.MetricsServerAddr,
		"result", result,
	)

	resp, err := http.Post(
		"http://"+cfg.MetricsServerAddr+"/result",
		"application/json",
		bodyBuffer,
	)
	if err != nil {
		return fmt.Errorf("unable to submit result to metrics server: %v", err)
	}

	if resp.StatusCode != http.StatusAccepted {
		return fmt.Errorf("metrics server returned unexpected status code: %d", resp.StatusCode)
	}

	logger.Info("Successfully completed task, exiting")

	return nil
}
