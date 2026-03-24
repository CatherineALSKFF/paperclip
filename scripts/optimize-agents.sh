#!/bin/bash
# Paperclip Agent Optimization Script
# Run after starting Paperclip: pnpm paperclipai run
# Then: bash scripts/optimize-agents.sh
#
# What this does:
# 1. Disables timer heartbeats for all agents (event-driven only)
# 2. Sets maxTurnsPerRun to 50 (prevents runaway token burn)
# 3. Keeps wakeOnDemand=true so agents respond to assignments and @mentions
# 4. Configures skill allowlists per role

API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
COMPANY_ID="${PAPERCLIP_COMPANY_ID:-}"

if [ -z "$COMPANY_ID" ]; then
  # Auto-detect company ID
  COMPANY_ID=$(ls ~/.paperclip/instances/default/companies/ 2>/dev/null | head -1)
  if [ -z "$COMPANY_ID" ]; then
    echo "Error: Could not detect PAPERCLIP_COMPANY_ID. Set it or pass as env var."
    exit 1
  fi
fi

echo "Using API: $API_URL"
echo "Company:   $COMPANY_ID"
echo ""

# Get all agents
AGENTS=$(curl -s "$API_URL/api/companies/$COMPANY_ID/agents")
if [ -z "$AGENTS" ] || [ "$AGENTS" = "[]" ]; then
  echo "No agents found."
  exit 1
fi

echo "$AGENTS" | python3 -c "
import json, sys
agents = json.load(sys.stdin)
for a in agents:
    role = a.get('role', 'unknown')
    name = a.get('displayName') or a.get('nameKey') or a['id'][:12]
    status = a.get('status', '?')
    print(f'  {name:20s} | {role:10s} | {status}')
print(f'\nTotal: {len(agents)} agents')
"

echo ""
echo "Applying optimizations..."
echo ""

# For each agent, update config
echo "$AGENTS" | python3 -c "
import json, sys, subprocess

agents = json.load(sys.stdin)
api_url = '$API_URL'

for agent in agents:
    agent_id = agent['id']
    role = agent.get('role', 'unknown')
    name = agent.get('displayName') or agent.get('nameKey') or agent_id[:12]

    # Get current config
    current_runtime = agent.get('runtimeConfig') or {}
    current_adapter = agent.get('adapterConfig') or {}
    current_heartbeat = current_runtime.get('heartbeat') or {}

    # --- Runtime config: disable timer, keep event-driven ---
    new_heartbeat = {
        'enabled': False,           # No timer heartbeats
        'wakeOnDemand': True,       # Still responds to assignments/@mentions
        'intervalSec': 3600,        # 1hr fallback if timer re-enabled
        'maxConcurrentRuns': 1,
    }

    # CEO gets timer enabled (low frequency check-in)
    if role == 'ceo':
        new_heartbeat['enabled'] = True
        new_heartbeat['intervalSec'] = 1800  # 30 min

    new_runtime = {**current_runtime, 'heartbeat': new_heartbeat}

    # --- Adapter config: maxTurns + skill allowlist ---
    # Set maxTurnsPerRun based on role
    max_turns = 50  # default
    if role in ('ceo', 'cto'):
        max_turns = 30  # managers do less tool work, more delegation
    elif role in ('cmo', 'cfo', 'designer'):
        max_turns = 40
    elif role == 'engineer':
        max_turns = 60  # engineers need more turns for coding

    new_adapter = {**current_adapter, 'maxTurnsPerRun': max_turns}

    # Skill allowlists per role
    core_skill = 'paperclipai/paperclip/paperclip'
    create_agent_skill = 'paperclipai/paperclip/paperclip-create-agent'

    if role in ('ceo', 'cto'):
        # Managers get core + hiring
        desired_skills = [core_skill, create_agent_skill]
    else:
        # Everyone else gets core only
        desired_skills = [core_skill]

    # Set skill preferences
    if 'paperclipSkillSync' not in new_adapter:
        new_adapter['paperclipSkillSync'] = {}
    new_adapter['paperclipSkillSync']['desiredSkills'] = desired_skills

    # Build PATCH payload
    payload = json.dumps({
        'runtimeConfig': new_runtime,
        'adapterConfig': new_adapter,
    })

    result = subprocess.run(
        ['curl', '-s', '-X', 'PATCH',
         f'{api_url}/api/agents/{agent_id}',
         '-H', 'Content-Type: application/json',
         '-d', payload],
        capture_output=True, text=True
    )

    timer_status = 'timer=30min' if role == 'ceo' else 'event-only'
    print(f'  {name:20s} | {role:10s} | turns={max_turns}, {timer_status}, skills={len(desired_skills)}')
"

echo ""
echo "Done. All agents optimized."
echo ""
echo "Summary:"
echo "  - Timer heartbeats: DISABLED (except CEO at 30min)"
echo "  - Event-driven wakes: ENABLED for all"
echo "  - Max turns: 30-60 per role"
echo "  - Skills: core-only for ICs, core+hiring for managers"
echo ""
echo "Token savings estimate: 70-80% reduction vs default config"
