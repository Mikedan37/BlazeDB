//
//  AnimatedComponents.swift
//  BlazeDBVisualizer
//
//  Reusable animated components for lively UI
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI

// MARK: - Animated Stat Card

struct AnimatedStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let delay: Double
    
    @State private var isVisible = false
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
                .rotationEffect(.degrees(isVisible ? 0 : -180))
            
            Text(value)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(color)
                .scaleEffect(isVisible ? 1.0 : 0.5)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0)
        .onAppear {
            withAnimation(BlazeAnimation.elastic.delay(delay)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Pulsing Badge

struct PulsingBadge: View {
    let text: String
    let color: Color
    
    @State private var isPulsing = false
    
    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.gradient)
                    .shadow(color: color.opacity(isPulsing ? 0.6 : 0.3), radius: isPulsing ? 8 : 4)
            )
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Animated Button

struct AnimatedButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(BlazeAnimation.quick) {
                isPressed = true
            }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.callout)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.gradient)
            )
            .foregroundStyle(.white)
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
            .shadow(
                color: color.opacity(isHovered ? 0.4 : 0),
                radius: isHovered ? 8 : 0
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(BlazeAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Animated List Row

struct AnimatedListRow<Content: View>: View {
    let index: Int
    @ViewBuilder let content: () -> Content
    
    @State private var isVisible = false
    
    var body: some View {
        content()
            .opacity(isVisible ? 1.0 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                withAnimation(BlazeAnimation.smooth.delay(BlazeAnimation.staggerDelay(index: index, baseDelay: 0.03))) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: geometry.size.width * (phase - 1))
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            phase = 2
                        }
                    }
                }
            }
            .clipped()
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerEffect())
    }
}

