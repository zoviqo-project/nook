import SwiftUI

struct SafeCoffeeView: View {
  @Environment(\.dismiss) private var dismiss
  let accept: () -> Void
  @State private var appeared = false
  private let tips = [
    ("building.2.fill", "Queda en lugares públicos."),
    ("person.2.fill", "Avisa a alguien de dónde estarás."),
    ("lock.shield.fill", "Comparte solo lo que tú quieras."),
    ("xmark.circle.fill", "Puedes cancelar cuando quieras."),
  ]
  var body: some View {
    ZStack {
      NookBackground()
      VStack(spacing: 26) {
        Spacer()
        CoffeeLogo(size: 86).offset(y: appeared ? 0 : 20).opacity(appeared ? 1 : 0)
        VStack(spacing: 8) {
          Text("UN CAFÉ SEGURO").font(.system(size: 34, weight: .black, design: .rounded))
          Text("La mejor conversación empieza sintiéndote bien.").foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        VStack(spacing: 12) {
          ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
            HStack(spacing: 16) {
              Image(systemName: tip.0).foregroundStyle(NookColors.mocha).frame(width: 28)
              Text(tip.1).font(.headline)
              Spacer()
            }.padding(18).background(
              NookColors.offWhite, in: RoundedRectangle(cornerRadius: NookRadius.medium)
            ).offset(x: appeared ? 0 : 60).opacity(appeared ? 1 : 0).animation(
              NookMotion.spring.delay(Double(index) * 0.08), value: appeared)
          }
        }
        Spacer()
        NookButton(title: "ENTENDIDO, ACEPTAR", icon: "checkmark") {
          accept()
          Haptics.success()
        }
        Button("Ahora no") { dismiss() }.font(.headline).foregroundStyle(.secondary)
      }.padding(24)
    }.onAppear { appeared = true }
  }
}
