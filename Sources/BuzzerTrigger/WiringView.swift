import SwiftUI

struct WiringView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TutoSection(title: "Le principe") {
                    Para("La carte son envoie en permanence un son grave et fort (300 Hz, −3 dBFS) dans un câble qui va jusqu'au buzzer. Quand on appuie, le contact du buzzer renvoie ce son vers une entrée de la carte. Le logiciel n'écoute que cette fréquence précise : dès qu'elle dépasse le seuil, il envoie une note MIDI à QLab et à grandMA3, puis se verrouille le temps de la séquence.")
                    Para("Le signal est envoyé fort exprès : c'est ce qui donne un grand écart entre le repos et l'appui (rapport signal/bruit), même sur un long câble.")
                }
                TutoSection(title: "1. Repérer le contact du buzzer") {
                    Bullet("Multimètre en mode bip sur les broches de la prise XLR du buzzer.")
                    Bullet("Cherche la paire qui bipe seulement quand on appuie (souvent 2 et 3, parfois 1 et 2).")
                    Bullet("Si elle bipe au repos et coupe à l'appui (contact fermé au repos), coche « Inverser » dans Détection.")
                    Bullet("S'il y a une LED ou de l'électronique dans le bouton, il faut un contact sec (simple interrupteur).")
                }
                TutoSection(title: "2. Câblage avec un seul câble XLR (conseillé)") {
                    Para("Broche 2 = aller du signal, broche 3 = retour, broche 1 = masse. Côté régie, un petit câble en Y à souder :")
                    WiringDiagram().frame(height: 230)
                    Bullet("Côté sortie : jack 6,35 mono (TS). Sur l'UMC1820, les sorties 3 à 10 sont en jack. Prends une sortie reliée à aucun ampli.")
                    Bullet("Côté entrée : jack 6,35 mono dans la partie jack d'un combo XLR/jack. Si tu passes par la partie XLR, coupe le 48 V.")
                    Bullet("Si le contact du buzzer n'est pas sur 2 et 3, adapte le Y (ou ressoude la prise du buzzer en 2-3).")
                }
                TutoSection(title: "3. Variante avec deux câbles") {
                    Para("Sans souder de Y : un câble de la sortie jusqu'à une borne du buzzer, un autre de l'autre borne jusqu'à l'entrée, masses reliées. Il faut juste un adaptateur côté buzzer.")
                }
                TutoSection(title: "4. Réglages dans l'appli") {
                    Bullet("Gain de l'entrée au minimum pour commencer : le signal est déjà fort.")
                    Bullet("Choisis la sortie et son canal, l'entrée et son canal, puis Démarrer. Au premier lancement, macOS demande l'accès au micro : accepte (c'est l'entrée de la carte son).")
                    Bullet("« Mesurer au repos » sans toucher au buzzer, puis « Mesurer en appuyant » en tenant le bouton 3 secondes. Le seuil se règle tout seul au milieu.")
                    Bullet("L'écart doit faire au moins 20 dB. Si l'appui sature (proche de 0 dB), baisse le gain. Si le repos est trop haut (diaphonie sur un câble très long), baisse la fréquence à 200 Hz ou passe à deux câbles.")
                }
                TutoSection(title: "5. MIDI") {
                    Para("Par défaut l'appli crée son propre port MIDI « Buzzer Trigger » : rien à configurer dans Configuration audio et MIDI. QLab et grandMA3 le voient comme une entrée tant que l'appli est ouverte. Lance donc Buzzer Trigger avant QLab et grandMA3.")
                    Para("Si un logiciel ne le voit pas, active le bus IAC (Configuration audio et MIDI > Fenêtre > Studio MIDI > Gestionnaire IAC > « Le périphérique est en ligne ») et choisis-le dans Sortie MIDI.")
                }
                TutoSection(title: "6. QLab") {
                    Bullet("Réglages de l'espace de travail > MIDI : vérifie que « Buzzer Trigger » (ou le bus IAC) est accepté en entrée.")
                    Bullet("Sur le cue ou le groupe à lancer : inspecteur > Triggers > MIDI Trigger > Note On, canal 1, note 60.")
                    Bullet("Test avec « Envoyer un test MIDI ».")
                }
                TutoSection(title: "7. grandMA3 onPC (avec le node)") {
                    Bullet("Menu > In & Out > MIDI : active l'entrée MIDI et sélectionne « Buzzer Trigger » (ou le bus IAC).")
                    Bullet("Menu > Setup > MIDI Remotes : ajoute une ligne, type Note, canal 2, note 60, cible l'exécuteur de la séquence, action Go.")
                    Bullet("Le node se règle comme d'habitude, il n'intervient pas dans le déclenchement.")
                }
                TutoSection(title: "8. Avant l'ouverture au public") {
                    Bullet("Mac sur secteur. L'appli empêche la mise en veille tant qu'elle est démarrée.")
                    Bullet("Carte son toujours sur le même port USB. Si elle a été débranchée : « Rafraîchir les périphériques » puis Démarrer.")
                    Bullet("Le verrou doit durer au moins la séquence la plus longue.")
                    Bullet("Plan B : « Déclencher à la main » ici, ou un Go direct dans QLab et sur la MA.")
                }
                TutoSection(title: "Installer sur un autre Mac") {
                    Para("Copie « Buzzer Trigger.app » (ou le zip) dans Applications. Au premier lancement : clic droit > Ouvrir. Si macOS bloque quand même : Réglages Système > Confidentialité et sécurité > « Ouvrir quand même ». Les réglages sont gardés par Mac.")
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding()
        }
    }
}

private struct TutoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.bold())
            content
        }
    }
}

private struct Para: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).fixedSize(horizontal: false, vertical: true) }
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

/// Schéma du câble en Y : jack sortie et jack entrée vers une XLR femelle, puis le buzzer.
struct WiringDiagram: View {
    var body: some View {
        Canvas { ctx, size in
            func box(_ r: CGRect, _ title: String, _ color: Color) {
                ctx.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(color), lineWidth: 2)
                ctx.draw(Text(title).font(.system(size: 12, weight: .semibold)), at: CGPoint(x: r.midX, y: r.midY))
            }
            func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ w: CGFloat = 3, dash: [CGFloat] = []) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, dash: dash))
            }
            func label(_ s: String, _ at: CGPoint) {
                ctx.draw(Text(s).font(.system(size: 11)).foregroundColor(.secondary), at: at)
            }
            let out = CGRect(x: 10, y: 20, width: 190, height: 50)
            let inp = CGRect(x: 10, y: 150, width: 190, height: 50)
            let xlr = CGRect(x: 320, y: 75, width: 150, height: 70)
            let buz = CGRect(x: size.width - 170, y: 75, width: 160, height: 70)
            box(out, "Carte son : SORTIE\njack mono (TS)", .blue)
            box(inp, "Carte son : ENTRÉE\njack mono, 48 V coupé", .green)
            box(xlr, "XLR femelle\n(fin du Y)", .primary)
            box(buz, "BUZZER\ncontact 2 ↔ 3", .orange)
            line(CGPoint(x: out.maxX, y: out.midY - 8), CGPoint(x: xlr.minX, y: xlr.minY + 15), .blue)
            label("pointe → broche 2", CGPoint(x: 262, y: 38))
            line(CGPoint(x: inp.maxX, y: inp.midY + 8), CGPoint(x: xlr.minX, y: xlr.maxY - 15), .green)
            label("pointe → broche 3", CGPoint(x: 262, y: 190))
            line(CGPoint(x: out.maxX, y: out.midY + 10), CGPoint(x: xlr.minX, y: xlr.midY), .gray, 2, dash: [5, 4])
            line(CGPoint(x: inp.maxX, y: inp.midY - 10), CGPoint(x: xlr.minX, y: xlr.midY), .gray, 2, dash: [5, 4])
            label("corps des 2 jacks → broche 1", CGPoint(x: 262, y: 112))
            line(CGPoint(x: xlr.maxX, y: xlr.midY), CGPoint(x: buz.minX, y: buz.midY), .primary, 5)
            label("câble XLR micro (longueur au choix)", CGPoint(x: (xlr.maxX + buz.minX) / 2, y: xlr.midY - 14))
        }
    }
}
