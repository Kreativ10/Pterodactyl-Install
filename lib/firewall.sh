#!/usr/bin/env bash
# shellcheck shell=bash
# Shared variables are consumed by panel.sh and other sourced modules.
# shellcheck disable=SC2034

ssh_ports() {
    local detected='' server_port
    if command_exists sshd; then
        detected="$(sshd -T | awk '$1 == "port" {print $2}')"
    fi
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        read -r _ _ _ server_port <<< "$SSH_CONNECTION"
        detected+=$'\n'"$server_port"
    fi
    printf '%s\n' "${detected:-22}" | awk '/^[0-9]+$/ && $1 > 0 && $1 <= 65535' | sort -un
}

firewall_zones() {
    { firewall-cmd --get-default-zone; firewall-cmd --get-active-zones | awk '/^[^ ]/ {print $1}'; } | sort -u
}

install_firewall() {
    if [[ "$OS_FAMILY" == debian ]]; then
        install_packages ufw
    else
        install_packages firewalld
        if ! systemctl is-active --quiet firewalld; then
            local port ports
            ports="$(ssh_ports)"
            [[ -n "$ports" ]] || error_exit "Cannot determine SSH ports safely."
            while read -r port; do
                firewall-offline-cmd --add-port="${port}/tcp"
            done <<< "$ports"
            enable_service_now firewalld
        fi
    fi
}

firewall_allow_tcp() {
    local port="$1" zone zones
    if [[ "$OS_FAMILY" == debian ]]; then
        ufw allow "${port}/tcp"
    else
        zones="$(firewall_zones)"
        [[ -n "$zones" ]] || error_exit "Cannot determine firewalld zones."
        while read -r zone; do
            firewall-cmd --zone="$zone" --permanent --add-port="${port}/tcp"
        done <<< "$zones"
    fi
}

firewall_allow_service() {
    local port ports
    case "$1" in
        ssh)
            ports="$(ssh_ports)"
            [[ -n "$ports" ]] || error_exit "Cannot determine SSH ports safely."
            while read -r port; do firewall_allow_tcp "$port"; done <<< "$ports" ;;
        http) firewall_allow_tcp 80 ;;
        https) firewall_allow_tcp 443 ;;
        *) error_exit "Unknown firewall service: $1" ;;
    esac
}

firewall_reload() {
    if [[ "$OS_FAMILY" == debian ]]; then
        ufw --force enable
    else
        firewall-cmd --reload
    fi
}

configure_panel_firewall() {
    [[ "$PANEL_CONFIGURE_FW" == true ]] || return 0
    print_header "Firewall"
    install_firewall
    firewall_allow_service ssh
    firewall_allow_service http
    case "$PANEL_SSL_MODE" in
        letsencrypt|existing_cert) firewall_allow_service https ;;
    esac
    firewall_reload
    success "Firewall rules updated for the panel."
}

configure_wings_firewall() {
    [[ "$WINGS_CONFIGURE_FW" == true ]] || return 0
    print_header "Firewall"
    install_firewall
    firewall_allow_service ssh
    firewall_allow_tcp 8080
    firewall_allow_tcp 2022
    if [[ "$WINGS_CERT_MODE" == letsencrypt ]]; then
        firewall_allow_service http
        firewall_allow_service https
    fi
    [[ "$WINGS_OPEN_DB_PORT" != true ]] || firewall_allow_tcp 3306
    firewall_reload
    success "Firewall rules updated for Wings."
}
