import SwiftUI

/// Mode d'emploi court : à lire en 2 minutes en presta.
struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GuideSection("Le principe") {
                    Bullet("Un cue = une liste d'actions : notes MIDI, CC, program change, lancer ou couper un son.")
                    Bullet("Un cue part avec son bouton GO, avec le buzzer, ou avec un repère placé dans un son.")
                    Bullet("Chaque action peut avoir un délai : par exemple la MA tout de suite, le laser à +2 s.")
                }
                GuideSection("En arrivant sur site") {
                    Step(1, "Réglages > Sorties MIDI : vérifie que chaque sortie pointe au bon endroit, puis « Tester ».")
                    Step(2, "Diffusion : choisis la CQ12T, « Démarrer la diffusion », puis « Lancer les boucles ».")
                    Step(3, "Réglages > Buzzer : « Démarrer l'écoute », mesure repos puis appui, choisis le cue à lancer.")
                    Step(4, "Cues : un GO à la main sur chaque cue pour vérifier.")
                    Step(5, "En cas de problème : PANIC (coupe les sons des cues, All Notes Off, désarme le buzzer, lance le cue PANIC). Les boucles continuent ; « Tout couper » dans Diffusion.")
                }
                GuideSection("Créer un cue") {
                    Bullet("Cues > « Modifier les cues » > « Nouveau cue ». Nom, couleur, puis « + Ajouter une action ».")
                    Bullet("Cases Buzzer et PANIC : ce cue part à l'appui du buzzer, ou sur PANIC.")
                    Bullet("⌘⏎ lance le cue ouvert pour tester. Repasse « Modifier les cues » sur off pour l'exploitation.")
                }
                GuideSection("Sons et repères") {
                    Bullet("Sons : ajoute les fichiers, choisis la zone, Boucle, « Au démarrage ».")
                    Bullet("Clique dans la forme d'onde, « Repère au curseur », choisis le cue à lancer. ⇧⌘M pose un repère pendant la lecture.")
                    Bullet("Sur la CQ12T, source des voies sur USB : sortie 1 du Mac = voie USB 1.")
                }
                GuideSection("grandMA3 (sur ce Mac)") {
                    Step(1, "Lance Cue Station avant grandMA3.")
                    Step(2, "Roue dentée > Settings > onPC Local Settings > MIDI In Device : « Cue Station ».")
                    Step(3, "Menu > In & Out > MIDI : MIDI In activé.")
                    Step(4, "MIDI Remotes : une ligne par cue. Type Note, le canal et la note de l'action, cible = l'exécuteur, action Go+.")
                    Step(5, "Dans Cue Station, sortie « grandMA3 » = Port virtuel.")
                }
                GuideSection("QLab (sur ce Mac)") {
                    Step(1, "Sortie « QLab » = Port virtuel.")
                    Step(2, "Sur le cue QLab : inspecteur > Triggers > MIDI Trigger, Note On, même canal et même note que l'action.")
                    Step(3, "Si rien n'arrive : réglages de l'espace de travail > MIDI, vérifie que « Cue Station » est écouté.")
                }
                GuideSection("PC QuickShow (par le réseau)") {
                    Step(1, "Câble réseau Mac ↔ switch ↔ PC, Wi-Fi coupé des deux côtés, IP fixes (Mac 192.168.1.10, PC 192.168.1.11).")
                    Step(2, "PC : rtpMIDI ouvert, une session active.")
                    Step(3, "Mac : Configuration audio et MIDI > Fenêtre > Réseau MIDI. Session RTP activée, choisis le PC dans l'annuaire, « Se connecter ».")
                    Step(4, "Cue Station : sortie « PC QuickShow » = la session réseau (Rafraîchir si elle n'apparaît pas).")
                    Step(5, "QuickShow : Settings > MIDI Settings > MIDI Devices : coche la session rtpMIDI. Input Options : Page 1, First Key = la note du premier cue.")
                    Step(6, "La note « First Key » lance la case en haut à gauche, la note suivante la case d'après.")
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding()
        }
    }
}

private struct GuideSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.bold())
            content
        }
    }
}

private struct Bullet: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Step: View {
    let n: Int, text: String
    init(_ n: Int, _ t: String) { self.n = n; text = t }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
