/// Paywallex pour Flutter (v1.0.0, DV4) : paiement, abonnement, retour dans l'app, confirmation serveur. Ouvre la page de paiement dans la session navigateur du système
/// (ASWebAuthenticationSession sur iPhone, onglet personnalisé sur Android) avec flutter_web_auth_2 :
/// la personne paie avec son compte Paywallex en un geste (App Switch), puis revient par votre schéma (monapp://…).
/// Le résultat est toujours confirmé auprès de Paywallex (/connect/status) : l'adresse de retour seule ne prouve rien.
library paywallex;

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

enum PaywallexOutcome { paid, pending, failed, expired, cancelled }

class PaywallexResult {
  const PaywallexResult(this.outcome, this.reference, {this.amountMinor, this.currency, this.paymentId});
  final PaywallexOutcome outcome;
  final String reference;
  final String? amountMinor, currency, paymentId;
}

enum PaywallexSubscribeOutcome { returned, cancelled }

/// [subscriptionId] : votre serveur le vérifie (GET /v1/subscriptions/{id}) avant d'ouvrir l'accès.
class PaywallexSubscribeResult {
  const PaywallexSubscribeResult(this.outcome, this.subscriptionId);
  final PaywallexSubscribeOutcome outcome;
  final String? subscriptionId;
}

class PaywallexException implements Exception {
  PaywallexException(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

class Paywallex {
  /// [appKey] : clé publique de l'app connectée (pxa_test_… ou pxa_live_…).
  /// [baseUrl] : adresse de l'API Paywallex, sans « /api » (donnée dans le Labs).
  /// [returnUrl] : adresse de retour déclarée dans la fiche de l'app, ex. « monapp://paiement ».
  Paywallex({required this.appKey, required String baseUrl, required this.returnUrl})
      : _base = baseUrl.replaceAll(RegExp(r'/+$'), '') {
    final s = Uri.parse(returnUrl).scheme.toLowerCase();
    if (s.isEmpty || s == 'http' || s == 'https') {
      throw ArgumentError('returnUrl doit utiliser le schéma de votre app (ex. monapp://paiement).');
    }
  }
  final String appKey, returnUrl;
  final String _base;

  /// Crée le paiement, ouvre la page Paywallex et rend le résultat confirmé par le serveur.
  /// [amount] : unités entières de la devise du compte (ex. « 5000 »). [reference] : votre numéro de commande, unique.
  Future<PaywallexResult> pay({required String amount, required String reference, String? title}) async {
    final created = await _request('POST', Uri.parse('$_base/api/connect/pay'),
        {'app': appKey, 'amount': amount, 'ref': reference, 'return': returnUrl, if (title != null) 'title': title});
    final url = created['url'];
    if (url is! String) throw PaywallexException('invalid_response', 'Réponse Paywallex inattendue.');
    String hint = 'cancelled';
    try {
      final back = await FlutterWebAuth2.authenticate(
          url: url, callbackUrlScheme: Uri.parse(returnUrl).scheme,
          options: const FlutterWebAuth2Options(preferEphemeral: false)); // garde la connexion Paywallex (App Switch)
      hint = Uri.parse(back).queryParameters['paywallex_status'] ?? 'cancelled';
    } on PlatformException {
      hint = 'cancelled'; // onglet fermé : on confirme quand même auprès du serveur
    }
    return status(reference, hint: hint);
  }

  /// Ouvre le lien d'abonnement créé par VOTRE SERVEUR (POST /v1/subscriptions avec success_url et cancel_url = returnUrl).
  Future<PaywallexSubscribeResult> subscribe(String subscribeUrl) async {
    final back = await _openPage(subscribeUrl);
    final id = back == null ? null : Uri.parse(back).queryParameters['subscription_id'];
    return id != null && id.isNotEmpty
        ? PaywallexSubscribeResult(PaywallexSubscribeOutcome.returned, id)
        : const PaywallexSubscribeResult(PaywallexSubscribeOutcome.cancelled, null);
  }

  /// Ouvre « Gérer mon abonnement » (lien de POST /v1/subscriptions/{id}/manage_link, valable 1 h).
  Future<void> manageSubscription(String manageUrl) async { await _openPage(manageUrl); }

  Future<String?> _openPage(String url) async {
    if (Uri.tryParse(url)?.scheme.toLowerCase() != 'https') {
      throw PaywallexException('invalid_url', 'Le lien doit être une adresse Paywallex en https.');
    }
    try {
      return await FlutterWebAuth2.authenticate(
          url: url, callbackUrlScheme: Uri.parse(returnUrl).scheme,
          options: const FlutterWebAuth2Options(preferEphemeral: false));
    } on PlatformException {
      return null;
    }
  }

  /// Confirme l'état d'un paiement auprès de Paywallex (à refaire côté serveur avant de livrer).
  Future<PaywallexResult> status(String reference, {String? hint}) async {
    final j = await _request('GET', Uri.parse('$_base/api/connect/status').replace(queryParameters: {'app': appKey, 'ref': reference}), null);
    final o = switch (j['status']) {
      'paid' => PaywallexOutcome.paid,
      'expired' => PaywallexOutcome.expired,
      _ => hint == 'cancelled' ? PaywallexOutcome.cancelled : hint == 'failed' ? PaywallexOutcome.failed : PaywallexOutcome.pending,
    };
    return PaywallexResult(o, reference,
        amountMinor: j['amountMinor'] as String?, currency: j['currency'] as String?, paymentId: j['paymentId'] as String?);
  }

  Future<Map<String, dynamic>> _request(String method, Uri url, Map<String, String>? body) async {
    final r = method == 'POST'
        ? await http.post(url, headers: {'Content-Type': 'application/json', 'Paywallex-Sdk': 'flutter/1.0.0'}, body: jsonEncode(body)).timeout(const Duration(seconds: 15))
        : await http.get(url, headers: {'Paywallex-Sdk': 'flutter/1.0.0'}).timeout(const Duration(seconds: 15));
    Map<String, dynamic> j;
    try { j = jsonDecode(r.body) as Map<String, dynamic>; } catch (_) { j = {}; }
    if (r.statusCode < 200 || r.statusCode > 299) {
      throw PaywallexException(j['code'] as String? ?? 'http_${r.statusCode}', j['error'] as String? ?? 'Paiement indisponible.');
    }
    return j;
  }
}
