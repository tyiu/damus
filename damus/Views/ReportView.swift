//
//  ReportView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct ReportView: View {
    let postbox: PostBox
    let target: ReportTarget
    let privkey: String
     
    @State var report_sent: Bool = false
    @State var report_id: String = ""
    @State var report_message: String = ""
    @State var selected_report_type: ReportType?
    
    var body: some View {
        if report_sent {
            Success
        } else {
            MainForm
        }
    }
    
    var Success: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("Report sent!", comment: "Message indicating that a report was successfully sent to relay servers.")
                .font(.headline)
            
            Text("Relays have been notified and clients will be able to use this information to filter content. Thank you!", comment: "Description of what was done as a result of sending a report to relay servers.")
            
            Text("Report ID:", comment: "Label indicating that the text underneath is the identifier of the report that was sent to relay servers.")
            
            Text(report_id)
            
            Button(NSLocalizedString("Copy Report ID", comment: "Button to copy report ID.")) {
                UIPasteboard.general.string = report_id
                let g = UIImpactFeedbackGenerator(style: .medium)
                g.impactOccurred()
            }
        }
        .padding()
    }
    
    func do_send_report() {
        guard let selected_report_type, let ev = send_report(privkey: privkey, postbox: postbox, target: target, type: selected_report_type, message: report_message) else {
            return
        }
        
        guard let note_id = bech32_note_id(ev.id) else {
            return
        }
        
        report_sent = true
        report_id = note_id
    }

    var send_report_button_text: String {
        switch target {
        case .note:
            return NSLocalizedString("Report Note", comment: "Button to report a note.")
        case .user:
            return NSLocalizedString("Report User", comment: "Button to report a user.")
        }
    }
    
    var MainForm: some View {
        VStack {
            
            Text("Report", comment: "Label indicating that the current view is for the user to report content.")
                .font(.headline)
                .padding()
            
        Form {
            Section(content: {
                Picker("", selection: $selected_report_type) {
                    ForEach(ReportType.allCases, id: \.self) { report_type in
                        // Impersonation type is not supported when reporting notes.
                        if case .note = target, report_type != .impersonation {
                            Text(verbatim: String(describing: report_type))
                                .tag(Optional(report_type))
                        } else if case .user = target {
                            Text(verbatim: String(describing: report_type))
                                .tag(Optional(report_type))
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)

                TextField(NSLocalizedString("Additional information (optional)", comment: "Prompt to enter optional additional information when reporting an account or content."), text: $report_message, axis: .vertical)

                Button(send_report_button_text) {
                    do_send_report()
                }
                .disabled(selected_report_type == nil)
            }, header: {
                Text("What do you want to report?", comment: "Header text to prompt user what issue they want to report.")
            }, footer: {
                Text("Your report will be sent to the relays you are connected to", comment: "Footer text to inform user what will happen when the report is submitted.")
            })
        }
        }
    }
}

func send_report(privkey: String, postbox: PostBox, target: ReportTarget, type: ReportType, message: String) -> NostrEvent? {
    let report = Report(type: type, target: target, message: message)
    guard let ev = create_report_event(privkey: privkey, report: report) else {
        return nil
    }
    postbox.send(ev)
    return ev
}

struct ReportView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        VStack {
        
        ReportView(postbox: ds.postbox, target: ReportTarget.user(""), privkey: "")
        
            ReportView(postbox: ds.postbox, target: ReportTarget.user(""), privkey: "", report_sent: true, report_id: "report_id")
            
        }
    }
}
