import PerfectHTTP

func appleAppSiteAssociationHandler(request rq: HTTPRequest, response: HTTPResponse) {
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
