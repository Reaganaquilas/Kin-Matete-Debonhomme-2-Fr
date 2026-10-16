# Activation de WhatsApp Business

L’intégration envoie les rappels de rapports par modèle WhatsApp approuvé. Le jeton Meta et le secret de service Supabase restent côté serveur; ne les ajoutez jamais aux pages HTML et ne les envoyez pas dans une conversation.

## Préparation Meta

1. Configurez un compte WhatsApp Business Platform/Cloud API, un numéro d’envoi vérifié et un modèle **Utility** approuvé dans WhatsApp Manager.
2. Créez et faites approuver deux modèles Utility. Chaque corps doit accepter trois paramètres dans cet ordre : salutation selon l’heure de Kinshasa, formule Fr/Sr, nom et souhait de bonne santé pour la personne et sa famille (`{{1}}`); mois du rapport affiché en toutes lettres, par exemple « septembre 2026 » (`{{2}}`); puis noms et numéros du responsable et de son adjoint ainsi que le numéro du secrétariat (`{{3}}`). Le troisième paramètre inclut aussi la formule de clôture : « Nous vous souhaitons une bonne suite de temps. Que Jéhovah, notre Dieu, vous protège. »

   Modèle de préparation :

   `{{1}}, la fin du mois approche. Pensez à préparer votre rapport d’activité de prédication pour {{2}}. Vous pourrez le transmettre dès la fin du mois, de préférence à votre responsable ou à son adjoint. {{3}} Répondez STOP pour ne plus recevoir ces rappels WhatsApp.`

   Modèle de rapport en retard :

   `{{1}}, votre rapport d’activité de prédication pour {{2}} n’a pas encore été reçu. Merci de le transmettre dès que possible à votre responsable ou à son adjoint. Il est préférable de passer par eux. À défaut, vous pouvez le remettre au secrétariat. {{3}} Merci pour les rapports des mois précédents déjà transmis. Répondez STOP pour ne plus recevoir ces rappels WhatsApp.`

3. Dans les secrets des Edge Functions Supabase, configurez `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_REPORT_REMINDER_TEMPLATE`, `WHATSAPP_REPORT_PREPARATION_TEMPLATE`, `WHATSAPP_TEMPLATE_LANGUAGE` (par exemple `fr`), `WHATSAPP_GRAPH_API_VERSION` (une version Graph actuellement prise en charge), `WHATSAPP_APP_SECRET` et un `WHATSAPP_WEBHOOK_VERIFY_TOKEN` aléatoire. Les secrets Supabase prédéfinis `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont aussi nécessaires; ne les exposez pas dans le navigateur.
4. Pour que le cron SQL appelle la fonction d’envoi, enregistrez une fois l’URL et la clé `service_role` dans Supabase Vault depuis le SQL Editor, en remplaçant les valeurs localement (ne transmettez jamais la clé par chat) :

   ```sql
   select vault.create_secret('https://<PROJECT_REF>.supabase.co', 'assembly_supabase_url');
   select vault.create_secret('<SERVICE_ROLE_KEY>', 'assembly_supabase_service_role_key');
   ```

5. Appliquez `supabase-schema.sql` au projet avant de déployer les fonctions. Si l’exécution précédente s’est arrêtée sur l’erreur de schéma `net`, relancez le script complet après cette correction. Il n’impose plus le déplacement de `pg_net` vers le schéma `net` et détecte le schéma où l’extension est réellement installée. Le cron déclenche à 08:00, heure de Kinshasa : deux jours avant la fin du mois, une notification de préparation; le 3, un bilan de groupe aux responsables et adjoints; le 4, une relance aux responsables n’ayant pas déclenché de rappel; puis les rappels automatiques aux retardataires les 5 et 10. Le responsable ou son adjoint peut déclencher un rappel de groupe à partir du 3; le secrétariat peut en déclencher un à partir du 5 et le refaire après le 10.
6. Déployez `send-whatsapp-report-reminders` et `whatsapp-webhook` avec la configuration de `supabase/config.toml`. Dans Meta Developers, configurez l’URL de rappel `https://<PROJECT_REF>.supabase.co/functions/v1/whatsapp-webhook`, le même jeton de vérification, puis abonnez l’application au champ `messages`. Le webhook vérifie la signature Meta et traite `STOP`, `STOPALL`, `UNSUBSCRIBE`, `CANCEL`, `END`, `QUIT` et `ARRÊT`.
7. Publiez les fichiers de l’application modifiés.

Chaque proclamateur choisit lui-même s’il accepte les envois par l’API WhatsApp dans **Boîte de messagerie → Rappels WhatsApp**. L’accord est lié au numéro enregistré au moment du consentement : si le numéro change, il faut donner son accord à nouveau. Les rappels WhatsApp automatiques ou déclenchés par l’API ne sont envoyés qu’aux personnes consentantes, avec un numéro exploitable. Chaque type d’envoi API n’est envoyé qu’une fois par mois de rapport; un échec peut être retenté. Les notifications dans l’application restent disponibles même si WhatsApp n’est pas configuré ou si la personne n’a pas consenti.

Dans le suivi secrétaire, **Préparer les rappels WhatsApp** ouvre successivement les conversations des responsables, adjoints et retardataires qui n’ont pas encore de rappel enregistré; un bouton est aussi proposé à côté de chaque retardataire. Les liens ne transmettent pas le message : après l’avoir envoyé dans WhatsApp, confirmez l’envoi dans l’application. Le tableau distingue alors les rapports toujours en attente des rappels envoyés. Un clic d’ouverture seul ne prouve pas qu’un message a été envoyé ou lu. Les livraisons de l’API et les rappels internes à l’application sont également pris en compte dans cet état. Le secrétariat peut aussi envoyer les rappels internes, y compris après le 10. Respectez les règles WhatsApp applicables aux messages envoyés manuellement.

Si le responsable adjoint ne reçoit pas les notifications internes ou ne voit pas son groupe, vérifiez que `groupLeaders.adjointId` correspond exactement à l’identifiant de sa fiche dans `proclamateurs` et que son compte est associé à cette fiche dans `assembly_memberships.proclamateur_id`. Le système utilise cette association pour trouver le compte destinataire; le seul numéro de téléphone ne permet pas d’envoyer une notification interne.

Les bilans de groupe envoyés aux responsables et à leurs adjoints affichent également, dans la boîte de messagerie, un tableau des proclamateurs dont le rapport manque. La liste est triée alphabétiquement et actualisée lors de la mise à jour du bilan du groupe.
