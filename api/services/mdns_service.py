"""Diffusion mDNS (multicast DNS) du nom "infini-post.local" sur le réseau
local — permet à N'IMPORTE QUEL appareil du réseau (pas seulement les
machines dont le fichier hosts a été édité par l'installeur) de résoudre
ce nom automatiquement, sans configuration manuelle. Windows 10+, macOS et
Linux (Avahi) savent tous résoudre les noms ".local" via mDNS nativement —
c'est justement la convention pour laquelle le TLD ".local" est réservé
(RFC 6762), donc c'est la bonne façon de rendre ce nom "fonctionnel
partout" plutôt qu'un fichier hosts local à chaque machine.

Ne concerne QUE l'installation locale self-hosted (Windows) — la version
cloud (Docker/Linux) n'a pas de réseau local à annoncer et n'appelle
jamais ce module (voir le guard os.name == "nt" dans main.py).
"""
import logging
import socket

_log = logging.getLogger("pos.mdns")

_HOSTNAME = "infini-post.local."
_zeroconf = None
_service_info = None
_current_ip: str | None = None
_current_port: int = 443


def _local_ip() -> str | None:
    """Détecte l'IP locale de la machine sur le réseau (pas 127.0.0.1) —
    astuce classique : ouvrir un socket UDP vers une IP externe (aucun
    paquet réellement envoyé) pour lire l'IP source que le système choisit."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()


def start_mdns_responder(port: int = 443) -> None:
    """Démarre la diffusion mDNS. Best-effort : toute erreur est loguée
    sans jamais empêcher le reste du serveur de démarrer (le fichier hosts
    reste un filet de sécurité fonctionnel pour la machine serveur elle-même
    si mDNS échoue pour une raison quelconque — pare-feu, adaptateur réseau
    désactivé, etc.). Idempotent : un appel répété relance proprement plutôt
    que de fuiter l'instance Zeroconf précédente."""
    global _zeroconf, _service_info, _current_ip, _current_port
    if _zeroconf is not None:
        stop_mdns_responder()
    try:
        from zeroconf import IPVersion, ServiceInfo, Zeroconf

        ip = _local_ip()
        if not ip:
            _log.warning("mDNS non démarré — IP locale introuvable")
            return

        _zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
        _service_info = ServiceInfo(
            "_https._tcp.local.",
            f"POS Connect._https._tcp.local.",
            addresses=[socket.inet_aton(ip)],
            port=port,
            server=_HOSTNAME,
        )
        _zeroconf.register_service(_service_info)
        _current_ip, _current_port = ip, port
        _log.info("mDNS démarré : %s -> %s (port %d)", _HOSTNAME, ip, port)
    except Exception:
        _log.exception("Échec démarrage mDNS — infini-post.local ne sera "
                        "résoluble que sur cette machine (fichier hosts)")


def stop_mdns_responder() -> None:
    global _zeroconf, _service_info
    if _zeroconf is None:
        return
    try:
        if _service_info is not None:
            _zeroconf.unregister_service(_service_info)
        _zeroconf.close()
    except Exception:
        _log.exception("Échec arrêt propre mDNS")
    finally:
        _zeroconf = None
        _service_info = None


def refresh_if_ip_changed() -> None:
    """Appelée périodiquement (voir _mdns_watch_loop dans main.py) — le DHCP
    peut réattribuer une IP différente au serveur pendant qu'il tourne
    (renouvellement de bail, redémarrage du routeur...). L'IP n'était sinon
    lue qu'une seule fois au démarrage : la diffusion mDNS restait figée sur
    l'ancienne IP, injoignable, jusqu'au prochain redémarrage du service."""
    if _zeroconf is None:
        return  # jamais démarré (ou échec) — rien à rafraîchir
    ip = _local_ip()
    if ip and ip != _current_ip:
        _log.info("IP locale changée (%s -> %s) — redémarrage mDNS", _current_ip, ip)
        start_mdns_responder(port=_current_port)
