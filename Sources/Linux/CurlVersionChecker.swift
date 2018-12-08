import CCurl

//
//  CurlVersionHelper.swift
//  VaporAPNS
//
//  Created by Matthijs Logemann on 01/01/2017.
//
//

class CurlVersionHelper {
    public enum Result {
        case ok
        case old(got: String, wanted: String)
        case noHTTP2
        case unknown
    }

    public func checkVersion() {
        switch checkVersionNum() {
        case .old(let got, let wanted):
            print("Your current version of curl (\(got)) is out of date!")
            print("APNS needs at least \(wanted).")
        case .noHTTP2:
            print("Your current version of curl lacks HTTP2!")
            print("APNS will not work with this version of curl.")
        default:
            break
        }
    }

    private func checkVersionNum() -> Result {
        let version = curl_version_info(CURLVERSION_FOURTH)
        let verBytes = version?.pointee.version
        let versionString = String.init(cString: verBytes!)
        //        return .old

        guard checkVersionNumber(versionString, "7.51.0") >= 0 else {
            return .old(got: versionString, wanted: "7.51.0")
        }

        let features = version?.pointee.features

        if ((features! & CURL_VERSION_HTTP2) == CURL_VERSION_HTTP2) {
            return .ok
        }else {
            return .noHTTP2
        }
    }

    private func checkVersionNumber(_ strVersionA: String, _ strVersionB: String) -> Int{
        var arrVersionA = strVersionA.split(separator: ".").map({ Int($0) })
        guard arrVersionA.count == 3 else {
            fatalError("Wrong curl version scheme! \(strVersionA)")
        }

        var arrVersionB = strVersionB.split(separator: ".").map({ Int($0) })
        guard arrVersionB.count == 3 else {
            fatalError("Wrong curl version scheme! \(strVersionB)")
        }

        let intVersionA = (100000000 * arrVersionA[0]!) + (1000000 * arrVersionA[1]!) + (10000 * arrVersionA[2]!)
        let intVersionB = (100000000 * arrVersionB[0]!) + (1000000 * arrVersionB[1]!) + (10000 * arrVersionB[2]!)

        if intVersionA > intVersionB {
            return 1
        } else if intVersionA < intVersionB {
            return -1
        } else {
            return 0
        }
    }
}
