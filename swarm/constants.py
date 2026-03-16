"""Swarm coordination constants.

Centralized configuration for tunable values used across coordinator,
scheduler, and client. Avoids scattered magic numbers.
"""

# SQLite connection
SQLITE_CONNECT_TIMEOUT = 30        # seconds
SQLITE_BUSY_TIMEOUT = 10000        # milliseconds (PRAGMA busy_timeout)

# Agent lifecycle
HEARTBEAT_STALE_SECONDS = 120      # seconds before an agent is considered stale
DEFAULT_LOCK_TTL = 300             # seconds for resource lock expiration
DEFAULT_HEARTBEAT_INTERVAL = 30.0  # seconds between client heartbeats
DEFAULT_AGENT_BUDGET = 100.0       # initial budget units per agent

# Work queue pagination
DEFAULT_WORK_LIST_LIMIT = 50       # default limit for list_work()
DEFAULT_MESSAGE_LIMIT = 100        # default limit for get_messages()
DEFAULT_BUDGET_HISTORY_LIMIT = 100 # default limit for get_budget_history()
MAX_PENDING_SCAN = 500             # max pending items scanned by scheduler

# Scheduler
MC_HYPERVOLUME_SAMPLES = 10000     # Monte Carlo samples for >2D hypervolume
EPSILON = 1e-10                    # numeric tolerance for box volume calculation
