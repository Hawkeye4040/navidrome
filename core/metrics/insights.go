package metrics

import (
	"context"
	"time"

	"github.com/navidrome/navidrome/model"
)

// nordic: the upstream insights collector (which reported usage data to
// insights.navidrome.org) has been removed. This no-op keeps the interface so
// callers and dependency wiring stay unchanged across upstream rebases.

type Insights interface {
	Run(ctx context.Context)
	LastRun(ctx context.Context) (timestamp time.Time, success bool)
}

type noopInsights struct{}

func GetInstance(_ model.DataStore) Insights { return noopInsights{} }

func (noopInsights) Run(context.Context) {}

func (noopInsights) LastRun(context.Context) (time.Time, bool) { return time.Time{}, false }
