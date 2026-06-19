#!/usr/bin/bash

# script location
TARGET_FILE="${0}" # -> /usr/local/bin/un.sentinel-login-pam.sh
SCRIPT_PATH="$(readlink -f "${TARGET_FILE}")" # -> /opt/un.sentinel-login-pam/src/main.sh
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}") # -> /opt/un.sentinel-login-pam/src
SCRIPT_PARENT=$(dirname "${SCRIPT_DIR}") # -> /opt/un.sentinel-login-pam

PATH_CONFIG="${SCRIPT_PARENT}/config.cfg"
PATH_DEFAULTS="${SCRIPT_PARENT}/defaults.cfg"

# IMPORTS
source "${SCRIPT_DIR}/lib/is_str_in_array.sh"
source "${SCRIPT_DIR}/lib/log.sh"

function main {

	# CHECK session type
	if [[ "${PAM_TYPE}" != "open_session" ]]; then
		exit 0
	fi

	# SOURCE config / defaults
	if [[ -r "${PATH_CONFIG}" ]]; then
		source "${PATH_CONFIG}"
	else
		source "${PATH_DEFAULTS}"
	fi

	# CHECK array
	if [[ "${#WATCH_USERS[@]}" -eq 0 ]]; then
		exit 0
	fi

	# CHECK user
	if ! is_str_in_array "${PAM_USER}" "${WATCH_USERS[@]}"; then
		exit 0
	fi

	log "------"
	log "PAM_TYPE: ${PAM_TYPE}"
	log "PAM_USER: ${PAM_USER}"
	log "PAM_TTY: ${PAM_TTY}"
	log "PARENT PROCESS: $(ps --pid ${PPID} -o comm,pid --no-headers)"
	log "TIMEOUT: ${TIMEOUT}"

	(
		# Wait for the timeout period
		sleep ${TIMEOUT}

		# Check if the canary file exists
		if [ -f "${CANARY_FILE}" ]; then
			# Success!
			rm -f "${CANARY_FILE}"
			log "RESULT: passed"
		else
			log "RESULT: failed"
			
			# ALERT
			echo "ALERT: Unauthorized login detected for user '${PAM_USER}' on $(date)" | \
			mail -s "${MAIL_SUBJECT}" "${MAIL_DST}" 2>/dev/null

			# SET session_pids
			local session_pids=""

			if [[ -n "${PAM_TTY}" && "${PAM_TTY}" != "ssh" ]]; then
				# Grab ONLY processes attached to this exact terminal window
				session_pids=$(ps --tty "${PAM_TTY}" -o pid=)
				log "PIDs connected to ${PAM_TTY}: $(echo ${session_pids})"
			fi

			# FALLBACK: Trace down from the specific PAM process tree safely
			if [[ -z "${session_pids}" && -n "${PPID}" ]]; then
				# $PPID at this point is the PID of the SSH daemon
				# Therefore every SSH connection will be terminated
				session_pids=$(ps --ppid "${PPID}" -o pid=)
				log "PIDs children of ${PPID}: $(echo ${session_pids})"
			fi

			# terminate session
			if [[ -n "${session_pids}" ]]; then
				
				# STAGE 1: SIGTERM (15)
                kill -15 ${session_pids} 2>/dev/null

				# Give the processes 3 seconds to catch the signal and exit cleanly
                sleep 3
				
				# STAGE 2: SIGKILL (9)
				local remaining_pids

                if [[ -n "${PAM_TTY}" && "${PAM_TTY}" != "ssh" ]]; then
                    remaining_pids=$(ps --tty "${PAM_TTY}" -o pid=)
                fi

				if [[ -z "${remaining_pids}" && -n "${PPID}" ]]; then
                    remaining_pids=$(ps --ppid "${PPID}" -o pid=)
                fi

				if [ -n "${remaining_pids}" ]; then
                    # Kill remaining processes
					log "Killing remaining PIDs: $(echo ${remaining_pids})"
                    kill -9 ${remaining_pids} 2>/dev/null
                fi
			fi
		fi
	) >/dev/null 2>&1 & # Forked to background, outputs silenced to prevent PAM hang-ups
}

main