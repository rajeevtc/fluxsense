import SwiftUI

struct StarterView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("EMFreadingImage")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Text("Begin EMF readings?")
                .font(.headline)
                .multilineTextAlignment(.center)

            NavigationLink {
                MagnetReaderView()
            } label: {
                Text("Start")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.55, green: 0.52, blue: 0.85))
        }
        .padding(.horizontal, 8)
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationView {
        StarterView()
    }
}
