# paywallex (Flutter)

Kit officiel Paywallex pour Flutter (iPhone et Android). Il ouvre la page Paywallex dans la session navigateur du système avec flutter_web_auth_2. La personne paie avec son compte Paywallex en un geste ou avec Mobile Money, puis revient dans votre app.

> Avant de livrer une commande, confirmez toujours depuis votre serveur (webhook `payment.succeeded` ou API `/v1`). Le retour dans l'app seul ne prouve rien.

## Installation

Ajoutez le paquet :

```sh
flutter pub add paywallex
```

Déclarez votre schéma comme le demande flutter_web_auth_2 (`Info.plist` sur iPhone, activité `CallbackActivity` dans le manifeste Android).

## Encaisser un paiement

Créez le client, puis lancez le paiement :

```dart
import 'package:paywallex/paywallex.dart';

final paywallex = Paywallex(appKey: 'pxa_test_…', baseUrl: 'https://api.paywallx.xyz', returnUrl: 'monapp://paiement');

final result = await paywallex.pay(amount: '5000', reference: 'CMD-1042', title: 'Commande 1042');
if (result.outcome == PaywallexOutcome.paid) { /* afficher « Merci » */ }
```

## Abonner une personne

Un abonnement se crée toujours depuis votre serveur avec votre clé secrète (`POST /v1/subscriptions`, avec `success_url` et `cancel_url` égaux à l'adresse de retour de l'app). Votre serveur renvoie `subscribe_url` à l'app, qui l'ouvre avec le kit. Avant d'ouvrir l'accès, votre serveur vérifie l'abonnement (`GET /v1/subscriptions/{id}`).

```dart
final r = await paywallex.subscribe(subscribeUrl);
if (r.outcome == PaywallexSubscribeOutcome.returned) { /* envoyez r.subscriptionId à votre serveur */ }
```

« Gérer mon abonnement » : `paywallex.manageSubscription(manageUrl)`.

## Licence

MIT.
