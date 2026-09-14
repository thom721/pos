"""
Génère une vidéo tuto (voix off française + capture écran réelle de l'app
pilotée par de vrais événements souris/clavier) pour un rôle donné.

Pilotage par événements OS réels (cliclick), pas par integration_test :
`flutter test -d macos` fait bien avancer la logique/les appels réseau, mais
ne force pas toujours un vrai redessin de la fenêtre macOS — la vidéo
capturait alors un écran figé malgré des actions réellement exécutées.

Prérequis (une fois) :
  - Backend accessible sur http://127.0.0.1:9003 :
        docker compose up -d fastapi
    (port temporairement publié à l'hôte dans docker-compose.yml — voir le
    commentaire "TEMPORAIRE", normalement seul nginx expose un port)
  - Données de démo : voir scripts/tutorial/seed_demo_data.py (déjà seedé
    pour ce compte : cassy / caissierdemo2026)
  - macOS, pour l'app hébergeant cette session (Terminal ou VS Code selon
    d'où les commandes tournent) :
      · Réglages Système → Confidentialité et sécurité → Enregistrement
        d'écran → cochée
      · Réglages Système → Confidentialité et sécurité → Accessibilité →
        cochée
    (les deux nécessitent de quitter/relancer complètement l'app après
    avoir coché, pas juste fermer la fenêtre)
  - ffmpeg + cliclick installés (brew install ffmpeg cliclick)

Usage :
  python3 scripts/tutorial/generate_tutorial_video.py cashier
  → tutorials/Tuto_Cashier.mp4

Coordonnées : exprimées en points logiques macOS (résolution Retina ÷ 2).
Pour recalibrer après un changement d'UI : lancer l'app, `screencapture` un
état, repérer un point à l'œil sur l'image (n'importe quelle taille
d'affichage), multiplier par 0.72 pour obtenir la coordonnée cliclick
correspondante à ce point sur la vraie fenêtre Retina.
"""
import subprocess
import sys
import time
import wave
import contextlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRONTEND_DIR = ROOT / "frontend"
OUT_DIR = ROOT / "tutorials"
TMP_DIR = OUT_DIR / "_tmp"

_VOICE = "Thomas"


def _run(cmd, **kw):
    print("  $", " ".join(str(c) for c in cmd))
    return subprocess.run(cmd, check=True, **kw)


def _wav_duration(path: Path) -> float:
    with contextlib.closing(wave.open(str(path), "rb")) as f:
        return f.getnframes() / float(f.getframerate())


def _activate() -> None:
    subprocess.run(["osascript", "-e", 'tell application "pos_connect" to activate'],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _click(x: float, y: float) -> None:
    """Active la fenêtre puis clique. IMPORTANT : dd: (mouse down) + du:
    (mouse up) séparés par un court délai -- pas c: (clic combiné), qui ne
    déclenche que l'état visuel "survolé/pressé" du bouton Flutter sans
    jamais compléter le geste de tap (aucune navigation ne se produit).
    Vécu en pratique : identique visuellement au clic réel jusqu'à ce
    qu'on compare les deux côte à côte sur un vrai écran suivant."""
    _activate()
    time.sleep(0.2)
    ix, iy = int(x), int(y)
    subprocess.run(["cliclick", f"dd:{ix},{iy}"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.15)
    subprocess.run(["cliclick", f"du:{ix},{iy}"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _type(text: str) -> None:
    subprocess.run(["cliclick", f"t:{text}"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ── Un rôle = une fonction de scénario (voir cashier_scenario) qui reçoit un
# callback say(i) — joue la ligne de narration i et bloque pendant TOUTE sa
# durée réelle (mesurée, pas estimée) avant de continuer. Garantit qu'une
# action n'arrive jamais avant que la réplique qui la décrit soit terminée,
# et qu'aucune réplique ne recouvre la suivante.

_GAP_S = 0.6  # silence entre deux répliques


def cashier_scenario(say) -> None:
    """Écran de connexion (déconnexion préalable si une session persistée
    d'un run précédent est encore active) → connexion réelle (identifiants
    tapés) → tableau de bord → Nouvelle vente → écran de caisse → ouverture
    de la caisse → vente d'un produit → encaissement."""
    _click(186, 867)  # icône déconnexion (session persistée d'un run précédent)
    time.sleep(1)
    _click(807, 495)  # "OK" sur le dialogue "Session terminée" qui suit la déconnexion
    time.sleep(0.5)
    say(0)  # "Voici l'écran de connexion..."
    say(1)  # "Entrez votre nom d'utilisateur et votre mot de passe..."
    _click(1079, 356)  # champ "Nom d'utilisateur"
    _type("cassy")
    _click(1079, 420)  # champ "Mot de passe"
    _type("caissierdemo2026")
    say(2)  # "Puis cliquez sur Se connecter."
    _click(1079, 634)  # bouton "Se connecter"
    say(3)  # "Vous voici sur le tableau de bord..."
    _click(327, 420)  # bouton "Nouvelle vente"
    say(4)  # "...directement sur l'écran de caisse..."
    # Le dialogue "Ouvrir la caisse" s'affiche automatiquement dès qu'on
    # arrive sur l'écran de caisse si la session n'est pas encore ouverte
    # (vécu en pratique, pas besoin de cliquer sur le bandeau rouge) --
    # fond de caisse laissé à sa valeur par défaut (0), on clique direct sur
    # le bouton de soumission du dialogue.
    _click(846, 526)  # "Ouvrir la caisse" (bouton du dialogue)
    say(5)  # "La caisse est maintenant ouverte..."
    _click(333, 295)  # carte produit "Eau minérale 500ml"
    say(6)  # "Le produit est ajouté au panier..."
    _click(1371, 811)  # lien "Paiement complet" (remplit Montant reçu = Total)
    _click(1259, 860)  # bouton "Encaisser"
    say(7)  # "Et voilà : la vente est enregistrée..."


STEPS = {
    "cashier": {
        "scenario": cashier_scenario,
        "narration": [
            "Voici l'écran de connexion de POS Connect.",
            "Entrez votre nom d'utilisateur et votre mot de passe.",
            "Puis cliquez sur Se connecter.",
            "Vous voici sur le tableau de bord. Cliquons sur Nouvelle vente pour démarrer une transaction.",
            "Vous arrivez directement sur l'écran de caisse, avec vos produits prêts à vendre. Si la caisse n'est pas encore ouverte, l'application vous le demande avant tout encaissement.",
            "La caisse est maintenant ouverte. Cliquez sur un produit pour l'ajouter à la vente.",
            "Le produit s'ajoute au panier avec son prix. Cliquez sur Paiement complet pour indiquer que le client paie le montant exact, puis sur Encaisser.",
            "Et voilà : la vente est enregistrée, avec un reçu prêt à imprimer. Notez que vous pouvez aussi accéder directement à l'écran de caisse en cliquant sur Caisse, dans le menu de gauche, sans passer par Nouvelle vente.",
        ],
    },
}


def generate_narration_clips(role: str, tmp_dir: Path) -> list[Path]:
    """Une réplique = un fichier .wav. Pas de montage/offset ici — le
    minutage réel est piloté en direct par _make_say() pendant le scénario
    (voir main()), pour ne jamais désynchroniser narration et action."""
    lines = STEPS[role]["narration"]
    clips = []
    for i, text in enumerate(lines):
        aiff = tmp_dir / f"line_{i}.aiff"
        _run(["say", "-v", _VOICE, "-o", str(aiff), text])
        wav = tmp_dir / f"line_{i}.wav"
        _run(["ffmpeg", "-y", "-i", str(aiff), str(wav)],
             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        clips.append(wav)
    return clips


def concat_narration(clips: list[Path], tmp_dir: Path) -> Path:
    """Concatène les répliques dans l'ordre, séparées par _GAP_S de silence —
    matché exactement au minutage réel du scénario (chaque action attend la
    fin de sa réplique + ce même silence avant de continuer, voir _make_say)."""
    filter_inputs = []
    for wav in clips:
        filter_inputs += ["-i", str(wav)]

    # Chaque clip sauf le dernier reçoit _GAP_S de silence ajouté à sa fin
    # (apad), puis concat() les mets bout à bout dans l'ordre.
    pad_steps = ";".join(
        (f"[{i}]apad=pad_dur={_GAP_S}[s{i}]" if i < len(clips) - 1 else f"[{i}]anull[s{i}]")
        for i in range(len(clips))
    )
    concat_inputs = "".join(f"[s{i}]" for i in range(len(clips)))
    filter_complex = f"{pad_steps};{concat_inputs}concat=n={len(clips)}:v=0:a=1[aout]"

    narration = tmp_dir / "narration.wav"
    _run([
        "ffmpeg", "-y", *filter_inputs,
        "-filter_complex", filter_complex,
        "-map", "[aout]", str(narration),
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return narration


def record_screen(out_path: Path, duration_s: float) -> subprocess.Popen:
    return subprocess.Popen([
        "ffmpeg", "-y",
        "-f", "avfoundation", "-framerate", "30", "-i", "1:none",
        "-t", str(duration_s + 3),
        "-pix_fmt", "yuv420p",
        str(out_path),
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _kill_stray_app() -> None:
    subprocess.run(["pkill", "-9", "-f", "pos_connect.app/Contents/MacOS/pos_connect"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)


def launch_app() -> subprocess.Popen:
    return subprocess.Popen(
        ["flutter", "run", "-d", "macos", "--debug"],
        cwd=FRONTEND_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def wait_for_app_window(timeout_s: float = 60) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        r = subprocess.run(
            ["pgrep", "-f", "pos_connect.app/Contents/MacOS/pos_connect"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if r.returncode == 0:
            return True
        time.sleep(0.3)
    return False


def compose(video: Path, narration: Path, out_path: Path) -> None:
    # Pas de -shortest : la video (duree du scenario pilote) doit primer sur
    # la narration (souvent plus courte) -- sinon la fin du scenario filme
    # est coupee. Le silence apres la fin de la narration est normal.
    _run([
        "ffmpeg", "-y",
        "-i", str(video), "-i", str(narration),
        "-c:v", "libx264", "-c:a", "aac",
        str(out_path),
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in STEPS:
        print(f"Usage: python3 {sys.argv[0]} <{'|'.join(STEPS)}>", file=sys.stderr)
        raise SystemExit(1)
    role = sys.argv[1]
    cfg = STEPS[role]

    OUT_DIR.mkdir(exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)

    print(f"[1/5] Narration ({role})...")
    clips = generate_narration_clips(role, TMP_DIR)
    durations = [_wav_duration(c) for c in clips]
    total_s = sum(durations) + _GAP_S * len(clips) + 4  # + marge
    print(f"      {len(clips)} répliques, {sum(durations):.1f}s de voix (+ marge : {total_s:.1f}s vidéo)")

    print("[2/5] Warm-up (build Xcode en cache, app pas encore enregistrée)...")
    _kill_stray_app()
    warm_proc = launch_app()
    if not wait_for_app_window():
        warm_proc.kill()
        raise RuntimeError("La fenêtre de pos_connect n'est jamais apparue (warm-up).")
    time.sleep(6)  # laisser l'app finir son premier rendu / auto-login
    warm_proc.terminate()
    _kill_stray_app()

    print("[3/5] Lancement piloté (build en cache, quasi instantané)...")
    app_proc = launch_app()
    if not wait_for_app_window():
        app_proc.kill()
        raise RuntimeError("La fenêtre de pos_connect n'est jamais apparue.")
    # 6s (pas 2) : avec une session persistée d'un run précédent, l'app doit
    # finir son auto-login + le fetch du tableau de bord + la vérif. de
    # version avant que le premier clic (déconnexion) ne tombe sur une
    # fenêtre réellement interactive -- sinon le clic ne touche rien et tout
    # le scénario de connexion est silencieusement sauté (vécu en pratique).
    time.sleep(6)
    _activate()

    raw_video = TMP_DIR / f"{role}_screen.mov"
    print("[4/5] Enregistrement + scénario piloté (voix jouée en direct)...")
    rec_proc = record_screen(raw_video, total_s)
    time.sleep(0.5)

    def say(i: int) -> None:
        """Joue la réplique i en direct et bloque pendant sa durée réelle +
        le silence inter-réplique — l'action suivante du scénario n'arrive
        donc jamais avant que celle-ci soit terminée à l'oreille."""
        subprocess.run(["afplay", str(clips[i])],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(_GAP_S)

    cfg["scenario"](say)

    rec_proc.send_signal(subprocess.signal.SIGINT)
    rec_proc.wait(timeout=15)
    app_proc.terminate()
    _kill_stray_app()

    print("[5/5] Montage final...")
    narration = concat_narration(clips, TMP_DIR)
    out_path = OUT_DIR / f"Tuto_{role.capitalize()}.mp4"
    compose(raw_video, narration, out_path)

    print(f"\nOK  {out_path}")


if __name__ == "__main__":
    main()
