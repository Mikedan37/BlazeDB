//
//  AnimationConfig.swift
//  BlazeDBVisualizer
//
//  Centralized animation configurations for consistent, lively UI
//  ✅ Smooth transitions
//  ✅ Hover effects
//  ✅ Loading states
//  ✅ Professional feel
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI

enum BlazeAnimation {
    // MARK: - Standard Animations
    
    /// Quick snappy animation for buttons and interactions
    static let quick = Animation.spring(response: 0.3, dampingFraction: 0.7)
    
    /// Smooth animation for transitions
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.75)
    
    /// Gentle animation for content loading
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.8)
    
    /// Bouncy animation for attention-grabbing
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    
    /// Eased animation for smooth transitions
    static let easeInOut = Animation.easeInOut(duration: 0.3)
    
    /// Elastic animation for playful interactions
    static let elastic = Animation.interpolatingSpring(stiffness: 200, damping: 15)
    
    // MARK: - Timing
    
    static let fastDuration: Double = 0.2
    static let normalDuration: Double = 0.3
    static let slowDuration: Double = 0.5
    
    // MARK: - Delays for Staggered Animations
    
    static func staggerDelay(index: Int, baseDelay: Double = 0.05) -> Double {
        return Double(index) * baseDelay
    }
}

// MARK: - View Modifiers

extension View {
    /// Animated card appearance with scale and opacity
    func animatedCardAppearance(delay: Double = 0) -> some View {
        self
            .scaleEffect(1.0)
            .opacity(1.0)
            .animation(BlazeAnimation.smooth.delay(delay), value: delay)
    }
    
    /// Hover scale effect for buttons and cards
    func hoverScale(isHovered: Bool) -> some View {
        self
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(BlazeAnimation.quick, value: isHovered)
    }
    
    /// Shimmer loading effect
    func shimmerEffect(isLoading: Bool) -> some View {
        self.overlay {
            if isLoading {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: isLoading ? 300 : -300)
                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: isLoading)
            }
        }
    }
    
    /// Pulse animation for notifications and alerts
    func pulseAnimation(isActive: Bool) -> some View {
        self
            .scaleEffect(isActive ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isActive)
    }
    
    /// Smooth fade transition
    func fadeTransition() -> some View {
        self.transition(.opacity.animation(BlazeAnimation.gentle))
    }
    
    /// Slide and fade transition
    func slideTransition(edge: Edge = .bottom) -> some View {
        self.transition(
            .asymmetric(
                insertion: .move(edge: edge).combined(with: .opacity),
                removal: .opacity
            )
            .animation(BlazeAnimation.smooth)
        )
    }
    
    /// Animated shadow for depth
    func animatedShadow(isHovered: Bool) -> some View {
        self.shadow(
            color: .black.opacity(isHovered ? 0.3 : 0.15),
            radius: isHovered ? 12 : 6,
            x: 0,
            y: isHovered ? 6 : 3
        )
        .animation(BlazeAnimation.quick, value: isHovered)
    }
    
    /// Success checkmark animation
    func successAnimation(show: Bool) -> some View {
        self.overlay {
            if show {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.green)
                    .scaleEffect(show ? 1.0 : 0.5)
                    .opacity(show ? 1.0 : 0)
                    .animation(BlazeAnimation.bouncy, value: show)
            }
        }
    }
}

// MARK: - Custom Transitions

extension AnyTransition {
    static var scaleAndFade: AnyTransition {
        .scale(scale: 0.8).combined(with: .opacity)
    }
    
    static var slideUp: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }
    
    static var slideDown: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }
}

// MARK: - Loading States

struct LoadingView: View {
    let message: String
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(
                        colors: [.blue, .purple, .pink, .blue],
                        center: .center
                    ),
                    lineWidth: 4
                )
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Success Checkmark

struct SuccessCheckmark: View {
    let show: Bool
    
    var body: some View {
        if show {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .scaleEffect(show ? 1.0 : 0.1)
                .opacity(show ? 1.0 : 0)
                .animation(BlazeAnimation.elastic, value: show)
        }
    }
}

