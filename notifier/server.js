'use strict';

/*
 * notifier - second service metier du fil rouge.
 * Recoit les evenements "produit cree" de demo-api et logge une notification
 * (simulateur d'email / Slack). Ne connait de demo-api que ce contrat HTTP.
 *
 * Variables d'environnement :
 *   PORT   port d'ecoute (def: 4000)
 */

const express = require('express');

const PORT = Number(process.env.PORT || 4000);

const app = express();
app.use(express.json());

app.get('/health', (req, res) => res.json({ status: 'UP' }));

app.post('/notify', (req, res) => {
  console.log(`[notifier] nouveau produit : ${JSON.stringify(req.body)}`);
  res.status(202).json({ received: true });
});

const server = app.listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', msg: 'notifier started', port: PORT }));
});

// PID 1 dans le conteneur : arret propre sur SIGTERM (docker stop).
function shutdown(sig) {
  console.log(JSON.stringify({ level: 'info', msg: 'shutting down', sig }));
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 8000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
