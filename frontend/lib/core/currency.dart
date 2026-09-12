import 'package:intl/intl.dart';
import 'package:pos_connect/providers/settings_provider.dart';

/// Conversion HTG ↔ devise d'affichage configurée par le tenant.
///
/// La gourde (HTG) reste l'UNIQUE source de vérité en base — tous les
/// montants stockés (Product.salePrice, Sale.totalAmount, etc.) sont
/// toujours en HTG. `AppSettings.currency` ne sert qu'à choisir comment on
/// les AFFICHE et dans quelle unité on les SAISIT :
/// - "$HT" (Dollar Haïtien, convention informelle) : ratio fixe 1 $HT = 5 HTG.
/// - USD/EUR : `AppSettings.rateUsd`/`rateEur` ("Taux du jour"), déjà
///   configurables dans Réglages mais jusqu'ici jamais utilisés pour un
///   calcul (uniquement lus/écrits par l'écran Réglages lui-même).
/// - HTG : facteur 1 (aucune conversion).
double _conversionFactor(AppSettings s) {
  switch (s.currency) {
    case 'HTD':
      return 5.0;
    case 'USD':
      return s.rateUsd > 0 ? s.rateUsd : 1.0;
    case 'EUR':
      return s.rateEur > 0 ? s.rateEur : 1.0;
    default:
      return 1.0;
  }
}

/// Convertit un montant HTG (valeur stockée) vers la devise d'affichage.
double toDisplayAmount(double htgAmount, AppSettings s) =>
    htgAmount / _conversionFactor(s);

/// Convertit un montant saisi dans la devise d'affichage vers HTG, pour
/// stockage/envoi au serveur — l'inverse de [toDisplayAmount].
double toHtgAmount(double displayAmount, AppSettings s) =>
    displayAmount * _conversionFactor(s);

/// Formateur (locale + symbole) pour la devise actuellement configurée.
NumberFormat currencyFormatter(AppSettings s, {int decimalDigits = 2}) {
  switch (s.currency) {
    case 'USD':
      return NumberFormat.currency(
          locale: 'en_US', symbol: '\$ ', decimalDigits: decimalDigits);
    case 'EUR':
      return NumberFormat.currency(
          locale: 'fr_FR', symbol: '€ ', decimalDigits: decimalDigits);
    case 'HTD':
      return NumberFormat.currency(
          locale: 'fr_HT', symbol: '\$HT ', decimalDigits: decimalDigits);
    default:
      return NumberFormat.currency(
          locale: 'fr_HT', symbol: s.currencySymbol, decimalDigits: decimalDigits);
  }
}

/// Formate un montant HTG (valeur stockée) directement dans la devise
/// d'affichage configurée — remplace tout `NumberFormat.currency(...).format(raw)`
/// codé en dur sur "HTG" ailleurs dans l'app.
String formatMoney(double htgAmount, AppSettings s, {int decimalDigits = 2}) =>
    currencyFormatter(s, decimalDigits: decimalDigits)
        .format(toDisplayAmount(htgAmount, s));
