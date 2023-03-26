//
//  TextViewWrapper.swift
//  damus
//
//  Created by Swift on 2/24/23.
//

import SwiftUI

struct TextViewWrapper: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    @Binding var cursor: Int
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        TextViewWrapper.setTextProperties(textView)
        return textView
    }
    
    static func setTextProperties(_ uiView: UITextView) {
        uiView.textColor = UIColor.label
        uiView.font = UIFont.preferredFont(forTextStyle: .body)
        let linkAttributes: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.foregroundColor: UIColor(Color.accentColor)]
        uiView.linkTextAttributes = linkAttributes
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
        TextViewWrapper.setTextProperties(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText, cursor: $cursor)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSMutableAttributedString
        @Binding var cursor: Int

        init(attributedText: Binding<NSMutableAttributedString>, cursor: Binding<Int>) {
            _attributedText = attributedText
            _cursor = cursor
        }

        func textViewDidChange(_ textView: UITextView) {
            attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            cursor = textView.selectedRange.upperBound
        }
    }
}

