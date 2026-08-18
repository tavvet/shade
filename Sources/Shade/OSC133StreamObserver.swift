/// Incrementally recognizes standard OSC 133 sequences in a PTY byte stream.
/// It does not consume or transform bytes; `ActivityTerminalView` remains
/// responsible for forwarding every byte to SwiftTerm in the original order.
struct OSC133StreamObserver {
    private enum State {
        case ground
        case escape
        case code
        case payload
    }

    private static let maximumPayloadLength = 4_096

    private var state = State.ground
    private var codeValue = 0
    private var hasCodeDigits = false
    private var codeOverflowed = false
    private var payload: [UInt8] = []
    private var isOSC133 = false
    private var payloadOverflowed = false

    /// Feeds one byte and returns the completed OSC 133 payload, excluding
    /// `OSC 133 ;` and its terminator.
    ///
    /// This deliberately mirrors SwiftTerm's parser: in the ground state all
    /// bytes above C0 are printable UTF-8 bytes, so only seven-bit `ESC ]`
    /// starts OSC. Inside OSC, BEL, ESC and C1 ST terminate; CAN/SUB cancel.
    /// Shade additionally caps retained payload bytes to avoid duplicating an
    /// arbitrarily large control string already buffered by SwiftTerm.
    mutating func consume(_ byte: UInt8) -> [UInt8]? {
        switch state {
        case .ground:
            if byte == 0x1B {
                state = .escape
            }

        case .escape:
            switch byte {
            case 0x5D:
                beginOSC()
            case 0x1B, 0x00...0x18, 0x1C...0x1F, 0x7F:
                // SwiftTerm executes C0 controls (or ignores DEL) without
                // leaving the escape state, so `]` can still introduce OSC.
                break
            default:
                state = .ground
            }

        case .code:
            switch byte {
            case 0x07, 0x9C:
                return finishOSC(nextState: .ground)
            case 0x1B:
                return finishOSC(nextState: .escape)
            case 0x18, 0x1A:
                reset(to: .ground)
            case 0x3B:
                isOSC133 = hasCodeDigits && !codeOverflowed && codeValue == 133
                state = .payload
            case 0x30...0x39:
                hasCodeDigits = true
                let digit = Int(byte - 0x30)
                if codeValue > (Int.max - digit) / 10 {
                    codeOverflowed = true
                } else if !codeOverflowed {
                    codeValue = codeValue * 10 + digit
                }
            case 0x20...0xFF:
                // SwiftTerm stores printable bytes and later rejects a
                // malformed decimal code. Mark it invalid immediately.
                codeOverflowed = true
            default:
                // Other C0 controls are ignored inside OSC.
                break
            }

        case .payload:
            switch byte {
            case 0x07, 0x9C:
                return finishOSC(nextState: .ground)
            case 0x1B:
                return finishOSC(nextState: .escape)
            case 0x18, 0x1A:
                reset(to: .ground)
            case 0x20...0xFF:
                appendPayloadByte(byte)
            default:
                // SwiftTerm ignores the remaining C0 controls in OSC data.
                break
            }
        }
        return nil
    }

    private mutating func beginOSC() {
        state = .code
        codeValue = 0
        hasCodeDigits = false
        codeOverflowed = false
        payload.removeAll(keepingCapacity: true)
        isOSC133 = false
        payloadOverflowed = false
    }

    private mutating func appendPayloadByte(_ byte: UInt8) {
        guard isOSC133, !payloadOverflowed else { return }
        guard payload.count < Self.maximumPayloadLength else {
            payload.removeAll(keepingCapacity: true)
            payloadOverflowed = true
            return
        }
        payload.append(byte)
    }

    private mutating func finishOSC(nextState: State) -> [UInt8]? {
        let result = isOSC133 && !payloadOverflowed ? payload : nil
        reset(to: nextState)
        return result
    }

    private mutating func reset(to nextState: State) {
        state = nextState
        codeValue = 0
        hasCodeDigits = false
        codeOverflowed = false
        payload.removeAll(keepingCapacity: true)
        isOSC133 = false
        payloadOverflowed = false
    }
}
