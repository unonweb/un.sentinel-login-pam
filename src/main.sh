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

function main { # $USER $PPID

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
	log "TIMEOUT: ${TIMEOUT}"
	log "PAM_TTY:${PAM_TTY}"
	log "PPID: ${PPID}"

	(
		# Wait for the timeout period
		sleep ${TIMEOUT}

		# Check if the canary file exists
		if [ -f "${CANARY_FILE}" ]; then
			# Success! User did the action. Clean up the file for next time.
			rm -f "${CANARY_FILE}"
			log "RESULT: passed"
		else
			log "RESULT: failed"
			local session_pids=""

			# Target processes tied ONLY to the specific terminal assigned to this login
            if [ -n "${PAM_TTY}" ]; then
                # session_pids=$(ps --tty "${PAM_TTY}" -o pid=)
				session_pids=$(ps --ppid "${PPID}" -o pid=)
            fi

			if [[ -z "${session_pids}" ]]; then
                session_pids=$(ps --user "${PAM_USER}" -o pid=)
            fi

			log "session_pids: $(echo ${session_pids})"

			if [[ -n "${session_pids}" ]]; then
				
				# Alert! Send email
				echo "ALERT: Unauthorized login detected for user '${PAM_USER}' on $(date)" | \
				mail -s "${MAIL_SUBJECT}" "${MAIL_DST}" 2>/dev/null

				# STAGE 1: SIGTERM (15)
                kill -15 ${session_pids} 2>/dev/null

				# Give the processes 3 seconds to catch the signal and exit cleanly
                sleep 3
				
				# STAGE 2: SIGKILL (9)
				local remaining_pids

                if [ -n "${PAM_TTY}" ]; then
                    remaining_pids=$(ps --tty "${PAM_TTY}" -o pid=)
                fi

				if [[ -z "${remaining_pids}" ]]; then
                    remaining_pids=$(ps --user "${PAM_USER}" -o pid=)
                fi

				if [ -n "${remaining_pids}" ]; then
                    # Kill remaining processes
                    kill -9 ${remaining_pids} 2>/dev/null
                fi
			fi
		fi
	) >/dev/null 2>&1 & # Forked to background, outputs silenced to prevent PAM hang-ups
}

main