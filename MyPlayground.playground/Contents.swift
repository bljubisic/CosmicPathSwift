import UIKit

import SwiftUI

struct ContentView: View {
    @State private var rotateOrbit = false // Tracks animation

    var body: some View {
        ZStack {
            // Sun at the center
            Circle()
                .fill(Color.yellow)
                .frame(width: 80, height: 80)
            
            // Mercury
            Circle()
                .fill(Color.gray)
                .frame(width: 15, height: 15)
                .offset(x: 50)
                .rotationEffect(.degrees(rotateOrbit ? 360 : 0))
                .animation(Animation.linear(duration: 3).repeatForever(autoreverses: false), value: rotateOrbit)
            
            // Venus
            Circle()
                .fill(Color.orange)
                .frame(width: 20, height: 20)
                .offset(x: 80)
                .rotationEffect(.degrees(rotateOrbit ? 360 : 0))
                .animation(Animation.linear(duration: 3.2).repeatForever(autoreverses: false), value: rotateOrbit)
            
            // Earth
            Circle()
                .fill(Color.blue)
                .frame(width: 25, height: 25)
                .offset(x: 110)
                .rotationEffect(.degrees(rotateOrbit ? 360 : 0))
                .animation(Animation.linear(duration: 3.4).repeatForever(autoreverses: false), value: rotateOrbit)
            
            // Mars
            Circle()
                .fill(Color.red)
                .frame(width: 20, height: 20)
                .offset(x: 140)
                .rotationEffect(.degrees(rotateOrbit ? 360 : 0))
                .animation(Animation.linear(duration: 3.6).repeatForever(autoreverses: false), value: rotateOrbit)
            
            // Jupiter
            Circle()
                .fill(Color.brown)
                .frame(width: 35, height: 35)
                .offset(x: 180)
                .rotationEffect(.degrees(rotateOrbit ? 360 : 0))
                .animation(Animation.linear(duration: 3.8).repeatForever(autoreverses: false), value: rotateOrbit)
            
            // Saturn
            Circle()
                .fill(Color.yellow)
                .frame(width: 30, height: 30)
                .offset(x: 220)
                .rotationEffect(.degrees(rotateOrbit ? 360 : 0))
                .animation(Animation.linear(duration: 4).repeatForever(autoreverses: false), value: rotateOrbit)
            
            // Uranus
            Circle()
                .fill(Color.cyan)
                .frame(width: 28, height: 28)
                .offset(x: 260)
                .rotationEffect(.degrees(rotateOrbit ? 360 : 0))
                .animation(Animation.linear(duration: 4.2).repeatForever(autoreverses: false), value: rotateOrbit)
            
            // Neptune
            Circle()
                .fill(Color.blue)
                .frame(width: 28, height: 28)
                .offset(x: 300)
                .rotationEffect(.degrees(rotateOrbit ? 360 : 0))
                .animation(Animation.linear(duration: 4.4).repeatForever(autoreverses: false), value: rotateOrbit)
        }
        .onAppear {
            rotateOrbit.toggle() // Start animation when view appears
        }
    }
}
