"""
Génère 3 guides utilisateur PDF (Caissier, Manager, Admin) pour POS Connect —
un par rôle, avec uniquement les fonctionnalités réellement accessibles à ce
rôle (contenu recoupé avec ROLE_PERMISSIONS, api/core/permissions.py, pour ne
jamais documenter une action que le rôle ne peut pas faire).

Installation (une fois, hors requirements.txt principal — outil de doc
uniquement, jamais utilisé par le serveur en production) :
    pip install reportlab

Usage :
    python3 api/scripts/generate_user_guides.py [dossier_de_sortie]

Sans argument, les PDF sont écrits dans ./guides/ (créé si absent) :
    guides/Guide_Caissier.pdf
    guides/Guide_Manager.pdf
    guides/Guide_Admin.pdf

Pour ajouter/modifier du contenu : éditer GUIDES ci-dessous (une entrée par
rôle, chaque section = un titre + une liste d'étapes). Rien d'autre à
toucher — le rendu PDF (page de garde, mise en page, numérotation) est
générique et commun aux 3 guides.
"""
import sys
from pathlib import Path

try:
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import cm
    from reportlab.platypus import (
        BaseDocTemplate, Frame, ListFlowable, ListItem, PageBreak,
        PageTemplate, Paragraph, Spacer, Table, TableStyle,
    )
except ImportError:
    print("reportlab n'est pas installé — lancez : pip install reportlab", file=sys.stderr)
    raise SystemExit(1)


# ── Contenu — un dict par rôle ──────────────────────────────────────────────
# "sections" : liste de (titre, [étapes...]).
# Recoupé avec ROLE_PERMISSIONS pour rester honnête sur ce que le rôle peut
# réellement faire (ex : le caissier peut LIRE les rabais mais pas en créer ;
# la vente à crédit n'est PAS accordée par défaut, voir la note dédiée).

GUIDES = {
    "Caissier": {
        "subtitle": "Guide d'utilisation quotidienne — poste de caisse",
        "sections": [
            ("Ouvrir une session de caisse", [
                "Connectez-vous avec votre nom d'utilisateur et mot de passe.",
                "Sélectionnez le dépôt/caisse si plusieurs sont disponibles.",
                "Ouvrez votre session avec le montant du fonds de caisse de départ.",
                "Votre session reste active jusqu'à ce que vous la fermiez — ne "
                "laissez jamais le poste ouvert sans surveillance.",
            ]),
            ("Enregistrer une vente", [
                "Recherchez un produit par nom, code-barres ou catégorie.",
                "Ajoutez les articles au panier — ajustez les quantités si besoin.",
                "Associez un client existant, ou laissez la vente anonyme.",
                "Appliquez un rabais actif si le client y a droit (les rabais "
                "eux-mêmes sont créés par un manager, vous ne pouvez que les "
                "appliquer).",
                "Choisissez le mode de paiement et encaissez.",
                "Le reçu s'imprime automatiquement si l'impression auto est "
                "activée, sinon utilisez le bouton Imprimer.",
            ]),
            ("Vente à crédit (paiement partiel)", [
                "Par défaut, un caissier NE PEUT PAS enregistrer une vente "
                "sous-payée — le système bloque avec un message clair si la "
                "permission manque.",
                "Si votre poste y est autorisé, un client est obligatoire pour "
                "toute vente à crédit (le solde dû lui est rattaché).",
                "Si vous en avez besoin régulièrement, demandez à un "
                "administrateur de vous accorder la permission dédiée.",
            ]),
            ("Retours et annulations", [
                "Une vente peut être annulée depuis l'historique si elle vient "
                "d'être créée.",
                "Pour un retour partiel ou après encaissement, utilisez l'écran "
                "Retours — sélectionnez la vente d'origine et les articles "
                "concernés.",
            ]),
            ("Proformas et factures", [
                "Une proforma (devis) peut être créée avant qu'un client ne "
                "confirme son achat — convertible en vente plus tard.",
                "Les factures suivent le même principe pour les ventes à "
                "livraison différée.",
            ]),
            ("Fermer la session de caisse", [
                "En fin de service, fermez votre session depuis le menu.",
                "Comptez le tiroir-caisse et renseignez le montant réel — tout "
                "écart avec le montant théorique est enregistré.",
            ]),
        ],
    },

    "Manager": {
        "subtitle": "Guide d'utilisation — gestion du commerce",
        "sections": [
            ("Ce qui s'ajoute au rôle Caissier", [
                "Le manager peut faire tout ce que peut faire un caissier "
                "(ventes, retours, sessions), plus la gestion complète décrite "
                "ci-dessous.",
            ]),
            ("Produits, catégories, fournisseurs", [
                "Créez, modifiez et désactivez des produits — prix, code-barres, "
                "stock d'alerte, produits composés.",
                "Organisez le catalogue en catégories.",
                "Gérez la liste de vos fournisseurs.",
            ]),
            ("Rabais", [
                "Créez et modifiez les rabais que les caissiers pourront "
                "ensuite appliquer aux ventes (pourcentage ou montant fixe, "
                "actif/inactif).",
            ]),
            ("Achats et réception de stock", [
                "Créez un bon d'achat auprès d'un fournisseur.",
                "Réceptionnez la marchandise reçue — le stock est mis à jour "
                "automatiquement.",
                "Ajustez manuellement le stock en cas d'écart constaté "
                "(casse, inventaire).",
            ]),
            ("Rapports", [
                "Consultez les rapports de ventes détaillés, y compris ceux de "
                "tous les caissiers (pas seulement les vôtres).",
                "Filtrez par période, dépôt, catégorie ou produit selon le "
                "besoin.",
            ]),
            ("Employés et paie", [
                "Gérez les fiches employés.",
                "Enregistrez les prêts/avances et leurs remboursements.",
                "Traitez les périodes de paie et les paiements.",
            ]),
            ("Dépôts et clients Sabotage", [
                "Gérez les dépôts de marchandise et retraits associés.",
                "Gérez la fiche client du système de Sabotage si votre "
                "commerce l'utilise.",
            ]),
            ("Réglages du commerce", [
                "Modifiez les informations de l'entreprise (nom, adresse, "
                "téléphone, logo) — ces réglages sont partagés par tous les "
                "postes et dépôts.",
                "Ajustez les taux de change, la taxe, le pied de page du reçu.",
            ]),
        ],
    },

    "Admin": {
        "subtitle": "Guide d'utilisation — administration complète",
        "sections": [
            ("Accès complet", [
                "Le rôle Admin a accès à absolument tout — l'ensemble des "
                "fonctionnalités Caissier et Manager, plus l'administration "
                "décrite ci-dessous.",
            ]),
            ("Utilisateurs et permissions", [
                "Créez un compte pour chaque employé, avec le rôle adapté "
                "(caissier, manager, admin, ou un rôle personnalisé).",
                "Accordez des permissions individuelles en complément du rôle "
                "— par exemple, autoriser un caissier précis à vendre à "
                "crédit sans changer son rôle.",
                "Désactivez un compte immédiatement en cas de départ.",
            ]),
            ("Dépôts et entrepôts", [
                "Créez autant de dépôts (points de vente) que nécessaire.",
                "Créez un ou plusieurs entrepôts avec leur propre adresse — "
                "chacun a son propre abonnement, distinct de celui des "
                "caisses.",
                "Distribuez le stock d'un entrepôt vers un dépôt (nécessite un "
                "entrepôt à jour dans son abonnement).",
            ]),
            ("Abonnement et facturation", [
                "Consultez l'état de l'abonnement de chaque caisse et entrepôt "
                "(actif, en essai, expiré).",
                "Le tarif de renouvellement, à partir de la 2e année, peut "
                "différer du tarif payé la première année — il est toujours "
                "affiché avant toute demande de paiement.",
                "Soumettez un paiement mensuel ou annuel pour une ou plusieurs "
                "caisses/entrepôts en une fois.",
            ]),
            ("Journal d'audit", [
                "Consultez l'historique des actions sensibles effectuées par "
                "chaque utilisateur (modifications de prix, suppressions, "
                "changements de permissions...).",
            ]),
            ("Synchronisation et connexion cloud", [
                "Si votre commerce utilise un serveur local, suivez l'état de "
                "la synchronisation avec le cloud depuis l'écran "
                "d'administration.",
                "Un logo ou réglage modifié depuis le web peut prendre "
                "quelques minutes avant d'apparaître sur les postes locaux, "
                "le temps du prochain cycle de synchronisation.",
            ]),
        ],
    },
}


# ── Rendu PDF ────────────────────────────────────────────────────────────────

_PRIMARY = colors.HexColor("#1E3A5F")
_ACCENT = colors.HexColor("#2E86AB")
_TEXT = colors.HexColor("#222222")


def _styles():
    ss = getSampleStyleSheet()
    ss.add(ParagraphStyle(
        "GuideTitle", parent=ss["Title"], fontSize=28, textColor=_PRIMARY,
        alignment=TA_CENTER, spaceAfter=6,
    ))
    ss.add(ParagraphStyle(
        "GuideSubtitle", parent=ss["Normal"], fontSize=14, textColor=_ACCENT,
        alignment=TA_CENTER, spaceAfter=4,
    ))
    ss.add(ParagraphStyle(
        "SectionHeading", parent=ss["Heading2"], fontSize=15, textColor=_PRIMARY,
        spaceBefore=18, spaceAfter=8, borderColor=_ACCENT, borderWidth=0,
    ))
    ss.add(ParagraphStyle(
        "Step", parent=ss["Normal"], fontSize=11, textColor=_TEXT,
        leading=15, spaceAfter=4,
    ))
    return ss


def _cover(story, styles, role: str, subtitle: str):
    story.append(Spacer(1, 6 * cm))
    story.append(Paragraph("POS Connect", styles["GuideTitle"]))
    story.append(Paragraph(f"Guide {role}", styles["GuideSubtitle"]))
    story.append(Spacer(1, 0.3 * cm))
    story.append(Paragraph(subtitle, styles["GuideSubtitle"]))
    story.append(Spacer(1, 2 * cm))
    table = Table([["posconnect.ht"]], colWidths=[8 * cm])
    table.setStyle(TableStyle([
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("TEXTCOLOR", (0, 0), (-1, -1), _ACCENT),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
    ]))
    story.append(table)
    story.append(PageBreak())


def _sections(story, styles, sections):
    for title, steps in sections:
        story.append(Paragraph(title, styles["SectionHeading"]))
        items = [ListItem(Paragraph(step, styles["Step"]), leftIndent=12)
                 for step in steps]
        story.append(ListFlowable(items, bulletType="bullet", start="•"))


def _footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.grey)
    canvas.drawString(2 * cm, 1.2 * cm, "POS Connect — Guide utilisateur")
    canvas.drawRightString(A4[0] - 2 * cm, 1.2 * cm, f"Page {doc.page}")
    canvas.restoreState()


def generate_guide(role: str, content: dict, out_dir: Path) -> Path:
    out_path = out_dir / f"Guide_{role}.pdf"
    doc = BaseDocTemplate(
        str(out_path), pagesize=A4,
        leftMargin=2.2 * cm, rightMargin=2.2 * cm,
        topMargin=2 * cm, bottomMargin=2 * cm,
    )
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="body")
    doc.addPageTemplates([PageTemplate(id="page", frames=[frame], onPage=_footer)])

    styles = _styles()
    story = []
    _cover(story, styles, role, content["subtitle"])
    _sections(story, styles, content["sections"])
    doc.build(story)
    return out_path


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("guides")
    out_dir.mkdir(parents=True, exist_ok=True)

    for role, content in GUIDES.items():
        path = generate_guide(role, content, out_dir)
        print(f"OK  {path}")


if __name__ == "__main__":
    main()
