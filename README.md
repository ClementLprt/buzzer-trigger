# Buzzer Trigger pour Mac

Appli Mac native : la carte son envoie un signal de 300 Hz vers le buzzer, l'appli détecte le retour et envoie une note MIDI à QLab (canal 1, note 60) et à grandMA3 (canal 2, note 60). Le tuto câblage est dans l'onglet « Tuto câblage » de l'appli.

Ce que ça change par rapport à la version Chrome :
- tous les périphériques et tous les canaux de la carte son (UMC1820 : 10 sorties, 8 entrées ou plus) ;
- un port MIDI virtuel « Buzzer Trigger » créé par l'appli, plus besoin d'activer le bus IAC ;
- le Mac ne se met pas en veille tant que l'appli est démarrée ;
- les réglages sont gardés.

## Version 5 : diffusion son intégrée

Téléchargement : https://github.com/ClementLprt/buzzer-trigger/releases/download/latest/Buzzer-Trigger.dmg

Quatre onglets :
- **Buzzer** : détection, verrou, PANIC, notes MIDI vers grandMA3 et QuickShow, choix du son intégré.
- **Diffusion** : carte de sortie (CQ12T en USB), zones (paire de sorties ou mono, volume, muet, vu-mètre, baisse pendant le buzzer), lancement des boucles, tout couper, ouvrir/enregistrer un show.
- **Éditeur de sons** : import de fichiers, zone, boucle, volume, forme d'onde avec zoom, lecture depuis un curseur, marqueurs MIDI déplaçables (nom, canal, note, sortie MIDI), envoyés à chaque passage de la lecture.
- **Tuto câblage**.

Appui sur le buzzer : le son du buzzer part une fois dans sa zone (avec ses marqueurs), les notes MA et laser partent, les zones cochées baissent puis remontent à la fin du son.

Le show est sauvegardé tout seul dans `~/Library/Application Support/Buzzer Trigger/show.json`. Les sons restent à leur place sur le disque.

## Compiler l'appli une fois (5 minutes, sur ton Mac)

1. Ouvre le Terminal et installe les outils Apple (gratuit, une seule fois) :
   `xcode-select --install`
2. Copie le dossier `BuzzerTrigger-Mac` sur le Mac (par exemple sur le Bureau).
3. Dans le Terminal :
   `cd ~/Desktop/BuzzerTrigger-Mac && bash build.sh`
4. Le dossier `dist` s'ouvre avec `Buzzer Trigger.app` et `Buzzer-Trigger-Mac.zip`. Range l'appli dans Applications.

Si la compilation affiche une erreur, copie-moi le message et je corrige.

## Mettre l'appli sur un autre Mac

Copie `Buzzer-Trigger-Mac.zip` (clé USB, AirDrop, Drive), décompresse, mets l'appli dans Applications.
L'appli n'est pas signée par un compte développeur Apple, donc au premier lancement :
- clic droit sur l'appli > Ouvrir > Ouvrir ;
- si macOS bloque quand même : Réglages Système > Confidentialité et sécurité > « Ouvrir quand même ».
- au premier Démarrer, accepte l'accès au micro (c'est ce qui permet de lire l'entrée de la carte son).

Si le Mac de compilation est un Mac Apple Silicon (M1, M2...) et que l'autre Mac est un Intel, le script essaie de faire une appli compatible avec les deux. Ça marche si Xcode complet est installé ; sinon, compile directement sur le Mac Intel.

## Sans Mac de compilation

Le dossier contient `.github/workflows/build.yml` : si tu mets ce dossier dans un dépôt GitHub, GitHub compile l'appli tout seul sur un Mac et le zip est téléchargeable dans l'onglet Actions.
