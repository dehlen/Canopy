import PerfectHTTP

func appleAppSiteAssociationHandler(request rq: HTTPRequest, response: HTTPResponse) {

    print()
    print("/apple-app-site-association")

    response.addHeader(.contentType, value: "application/json")
    response.appendBody(string: """
        {
            "applinks": {
                "apps": [],
                "details": [
                    {
                        "appID": "\(teamId).com.codebasesaga.iOS.Downstream",
                        "paths": ["/oauth"]
                    }
                ]
            }
        }
        """)
    response.completed()
}
