enum SSHProfileDisplay {
    static func destinationLabel(_ profile: SSHProfile) -> String {
        var host = profile.host
        if profile.port != nil, host.contains(":"), !host.hasPrefix("[") {
            host = "[\(host)]"
        }
        let destination = profile.username.map { "\($0)@\(host)" } ?? host
        return profile.port.map { "\(destination):\($0)" } ?? destination
    }
}
