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
                    Bullet("Le contact a deux fils : c'est eux qu'on relie aux deux XLR du boîtier (voir ci-dessous).")
                }
                TutoSection(title: "2. Le boîtier buzzer : deux embases XLR") {
                    Para("Le buzzer sort sur deux XLR, ce qui permet de rallonger avec des câbles micro standard.")
                    Bullet("ALLER = XLR femelle (reçoit le signal de la carte son, comme une entrée).")
                    Bullet("RETOUR = XLR mâle (renvoie vers la carte son, comme un micro).")
                    Bullet("ALLER broche 2 → un fil du contact. Autre fil du contact → RETOUR broche 2.")
                    Bullet("RETOUR broche 3 reliée à RETOUR broche 1. Broche 1 ALLER reliée à broche 1 RETOUR (masse).")
                    Bullet("ALLER broche 3 : rien. Ne jamais relier la broche 3 de l'ALLER au RETOUR, sinon le signal passe en permanence.")
                    WiringDiagram().frame(height: 250)
                }
                TutoSection(title: "3. Branchement en régie") {
                    Bullet("Sortie de la carte son (jack) → câble jack / XLR mâle → rallonges XLR → ALLER du buzzer.")
                    Bullet("RETOUR du buzzer → rallonges XLR → entrée XLR de la carte son.")
                    Bullet("48 V IMPÉRATIVEMENT COUPÉ sur cette entrée : sinon la tension remonte par le contact jusqu'à la sortie de la carte.")
                    Bullet("Scarlett 2i2 : Line Out 2 et Input 2. Débrancher casque et enceintes de monitoring (les sorties 1-2 y sont reliées).")
                    Bullet("UMC1820 (conseillé pour le show) : une sortie libre entre 3 et 10, et une entrée XLR libre.")
                }
                TutoSection(title: "4. Réglages dans l'appli") {
                    Bullet("Gain de l'entrée au minimum pour commencer : le signal est déjà fort.")
                    Bullet("Choisis la sortie et son canal, l'entrée et son canal, puis Démarrer. Au premier lancement, macOS demande l'accès au micro : accepte (c'est l'entrée de la carte son).")
                    Bullet("« Mesurer au repos » sans toucher au buzzer, puis « Mesurer en appuyant » en tenant le bouton 3 secondes. Le seuil se règle tout seul au milieu.")
                    Bullet("L'écart doit faire au moins 20 dB. Si l'appui sature (proche de 0 dB), baisse le gain. Si le repos est trop haut (diaphonie sur un câble très long), baisse la fréquence à 200 Hz et vérifie que la broche 3 de l'ALLER n'est reliée à rien.")
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

/// Schéma : carte son -> rallonges -> boîtier buzzer à deux XLR -> rallonges -> carte son.
struct WiringDiagram: View {
    var body: some View {
        Canvas { ctx, size in
            func box(_ r: CGRect, _ title: String, _ color: Color) {
                ctx.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(color), lineWidth: 2)
                ctx.draw(Text(title).font(.system(size: 12, weight: .semibold)), at: CGPoint(x: r.midX, y: r.midY))
            }
            func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ w: CGFloat = 3) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w))
            }
            func label(_ s: String, _ at: CGPoint) {
                ctx.draw(Text(s).font(.system(size: 11)).foregroundColor(.secondary), at: at)
            }
            let out = CGRect(x: 10, y: 20, width: 200, height: 50)
            let inp = CGRect(x: 10, y: 170, width: 200, height: 50)
            let bx = size.width - 260
            let buzzer = CGRect(x: bx, y: 10, width: 250, height: 220)
            let aller = CGRect(x: bx + 15, y: 25, width: 120, height: 40)
            let retour = CGRect(x: bx + 15, y: 175, width: 120, height: 40)
            ctx.stroke(Path(roundedRect: buzzer, cornerRadius: 12), with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            ctx.draw(Text("BOÎTIER BUZZER").font(.system(size: 11, weight: .bold)).foregroundColor(.orange), at: CGPoint(x: bx + 195, y: 22))
            box(out, "Carte son : SORTIE (jack)", .blue)
            box(inp, "Carte son : ENTRÉE XLR\n48 V COUPÉ", .green)
            box(aller, "ALLER\nXLR femelle", .blue)
            box(retour, "RETOUR\nXLR mâle", .green)
            line(CGPoint(x: out.maxX, y: out.midY), CGPoint(x: aller.minX, y: aller.midY), .blue)
            label("câble jack/XLR M + rallonges XLR", CGPoint(x: (out.maxX + aller.minX) / 2, y: out.midY - 12))
            line(CGPoint(x: retour.minX, y: retour.midY), CGPoint(x: inp.maxX, y: inp.midY), .green)
            label("rallonges XLR", CGPoint(x: (inp.maxX + retour.minX) / 2, y: inp.midY - 12))
            // contact
            let cx = bx + 75
            line(CGPoint(x: cx, y: aller.maxY), CGPoint(x: cx, y: 105), .primary, 2)
            line(CGPoint(x: cx, y: 105), CGPoint(x: cx + 22, y: 122), .primary, 2)
            line(CGPoint(x: cx, y: 128), CGPoint(x: cx, y: retour.minY), .primary, 2)
            label("broche 2", CGPoint(x: cx - 32, y: aller.maxY + 12))
            label("contact du bouton", CGPoint(x: cx + 80, y: 116))
            label("broche 2", CGPoint(x: cx - 32, y: retour.minY - 12))
            label("RETOUR 3 → 1", CGPoint(x: cx + 105, y: retour.midY))
            label("masses : 1 ↔ 1", CGPoint(x: cx + 105, y: 150))
        }
    }
}
