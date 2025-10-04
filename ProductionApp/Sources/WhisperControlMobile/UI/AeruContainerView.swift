import SwiftUI

struct AeruContainerView: View {
    var body: some View {
        AeruView() // Directly embedding AeruView
            .ignoresSafeArea()
    }
}
