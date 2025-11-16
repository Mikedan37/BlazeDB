//
//  SexyTabPicker.swift
//  BlazeDBVisualizer
//
//  Beautiful animated tab picker with smooth transitions
//  ✅ Sliding underline indicator
//  ✅ Smooth tab animations
//  ✅ Hover effects
//  ✅ Professional feel
//
//  Created by AI Assistant on 11/14/25.
//

import SwiftUI

struct SexyTabPicker<SelectionValue: Hashable>: View {
    @Binding var selection: SelectionValue
    let tabs: [(value: SelectionValue, label: String, icon: String)]
    
    @State private var hoveredTab: SelectionValue?
    @Namespace private var animation
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs, id: \.value) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .allowsHitTesting(true)  // Ensure tabs are always clickable
        .frame(height: 60)  // Fixed height so content doesn't overlap
    }
    
    private func tabButton(for tab: (value: SelectionValue, label: String, icon: String)) -> some View {
        let isSelected = selection == tab.value
        let isHovered = hoveredTab == tab.value
        
        return Button(action: {
            print("🎯 Tab clicked: \(tab.label)")
            withAnimation(BlazeAnimation.smooth) {
                selection = tab.value
            }
        }) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: tab.icon)
                        .font(.callout)
                        .foregroundColor(isSelected ? .white : (isHovered ? .blue : .secondary))
                    
                    Text(tab.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : (isHovered ? .blue : .primary))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.gradient)
                            .matchedGeometryEffect(id: "selectedTab", in: animation)
                            .shadow(color: .blue.opacity(0.3), radius: 8, y: 2)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    }
                }
                
                // Animated underline indicator
                if isSelected {
                    Rectangle()
                        .fill(Color.blue.gradient)
                        .frame(height: 3)
                        .matchedGeometryEffect(id: "underline", in: animation)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 3)
                }
            }
            .scaleEffect(isHovered && !isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(BlazeAnimation.quick) {
                hoveredTab = hovering ? tab.value : nil
            }
        }
    }
}

// MARK: - Smooth Page Transitions

struct AnimatedTabContent<Content: View>: View {
    let tab: AnyHashable
    @ViewBuilder let content: () -> Content
    
    @State private var isVisible = false
    
    var body: some View {
        content()
            .opacity(isVisible ? 1.0 : 0)
            .scaleEffect(isVisible ? 1.0 : 0.95)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                withAnimation(BlazeAnimation.smooth) {
                    isVisible = true
                }
            }
            .onChange(of: tab) { _, _ in
                isVisible = false
                withAnimation(BlazeAnimation.smooth.delay(0.1)) {
                    isVisible = true
                }
            }
    }
}

