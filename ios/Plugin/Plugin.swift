import Foundation
import AudioToolbox
import Capacitor

class dataForm {
    let type:String;
    let name:String;
    let value:String;
    
    init(name:String,type:String, value:String){
        self.name = name;

        self.type = type;
        self.value = value;
    }
}






@objc(CAPHttpPlugin)
public class CAPHttpPlugin: CAPPlugin {

  @objc public func request(_ call: CAPPluginCall) {
    print("Testasan","---------------------")
    guard let urlValue = call.getString("url") else {
      return call.reject("Must provide a URL")
    }
    guard let method = call.getString("method") else {
      return call.reject("Must provide a method. One of GET, DELETE, HEAD PATCH, POST, or PUT")
    }
    
    let headers = (call.getObject("headers") ?? [:]) as [String:String]
    print("Testasan",headers)

    let params = (call.getObject("params") ?? [:]) as [String:String]
    
    guard var url = URL(string: urlValue) else {
      return call.reject("Invalid URL")
    }
    
    
    switch method {
    case "GET", "HEAD":
      get(call, &url, method, headers, params)
    case "DELETE", "PATCH", "POST", "PUT":
      mutate(call, url, method, headers)
    default:
      call.reject("Unknown method")
    }
  }

  
  @objc public func downloadFile(_ call: CAPPluginCall) {
    guard let urlValue = call.getString("url") else {
      return call.reject("Must provide a URL")
    }
    guard let filePath = call.getString("filePath") else {
      return call.reject("Must provide a file path to download the file to")
    }
    
    let fileDirectory = call.getString("fileDirectory") ?? "DOCUMENTS"
    
    guard let url = URL(string: urlValue) else {
      return call.reject("Invalid URL")
    }
    
    let task = URLSession.shared.downloadTask(with: url) { (downloadLocation, response, error) in
      if error != nil {
        CAPLog.print("Error on download file", downloadLocation, response, error)
        call.reject("Error", "DOWNLOAD", error, [:])
        return
      }
      
      guard let location = downloadLocation else {
        call.reject("Unable to get file after downloading")
        return
      }
      
      // TODO: Move to abstracted FS operations
      let fileManager = FileManager.default
      
      let foundDir = FilesystemUtils.getDirectory(directory: fileDirectory)
      let dir = fileManager.urls(for: foundDir, in: .userDomainMask).first
      
      do {
        let dest = dir!.appendingPathComponent(filePath)
        print("File Dest", dest.absoluteString)
        
        try FilesystemUtils.createDirectoryForFile(dest, true)
        
        try fileManager.moveItem(at: location, to: dest)
        call.resolve([
          "path": dest.absoluteString
        ])
      } catch let e {
        call.reject("Unable to download file", "DOWNLOAD", e)
        return
      }
      
      
      CAPLog.print("Downloaded file", location)
      call.resolve()
    }
    
    task.resume()
  }
  
  @objc public func uploadFile(_ call: CAPPluginCall) {
    guard let urlValue = call.getString("url") else {
      return call.reject("Must provide a URL")
    }
    guard let filePath = call.getString("filePath") else {
      return call.reject("Must provide a file path to download the file to")
    }
    let name = call.getString("name") ?? "file"
    
    let fileDirectory = call.getString("fileDirectory") ?? "DOCUMENTS"
    
    guard let url = URL(string: urlValue) else {
      return call.reject("Invalid URL")
    }
    
    guard let fileUrl = FilesystemUtils.getFileUrl(filePath, fileDirectory) else {
      return call.reject("Unable to get file URL")
    }
   
    var request = URLRequest.init(url: url)
    request.httpMethod = "POST"
    
    let boundary = UUID().uuidString
    
    var fullFormData: Data?
    do {
      fullFormData = try generateFullMultipartRequestBody(fileUrl, name, boundary)
    } catch let e {
      return call.reject("Unable to read file to upload", "UPLOAD", e)
    }


    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    let task = URLSession.shared.uploadTask(with: request, from: fullFormData) { (data, response, error) in
      if error != nil {
        CAPLog.print("Error on upload file", data, response, error)
        call.reject("Error", "UPLOAD", error, [:])
        return
      }
      
      // let res = response as! HTTPURLResponse
      
      //CAPLog.print("Uploaded file", location)
      call.resolve()
    }
    
    task.resume()
  }
  
  @objc public func setCookie(_ call: CAPPluginCall) {
  
    guard let key = call.getString("key") else {
      return call.reject("Must provide key")
    }
    guard let value = call.getString("value") else {
      return call.reject("Must provide value")
    }
    guard let urlString = call.getString("url") else {
      return call.reject("Must provide URL")
    }
    
    guard let url = URL(string: urlString) else {
      return call.reject("Invalid URL")
    }
    
    let jar = HTTPCookieStorage.shared
    let field = ["Set-Cookie": "\(key)=\(value)"]
    let cookies = HTTPCookie.cookies(withResponseHeaderFields: field, for: url)
    jar.setCookies(cookies, for: url, mainDocumentURL: url)
    
    call.resolve()
  }
  
  @objc public func getCookies(_ call: CAPPluginCall) {
    guard let urlString = call.getString("url") else {
      return call.reject("Must provide URL")
    }
    
    guard let url = URL(string: urlString) else {
      return call.reject("Invalid URL")
    }
    
    let jar = HTTPCookieStorage.shared
    guard let cookies = jar.cookies(for: url) else {
      return call.resolve([
        "value": []
      ])
    }
    
    let c = cookies.map { (cookie: HTTPCookie) -> [String:String] in
      return [
        "key": cookie.name,
        "value": cookie.value
      ]
    }
    
    call.resolve([
      "value": c
    ])
  }
  
  @objc public func deleteCookie(_ call: CAPPluginCall) {
    guard let urlString = call.getString("url") else {
      return call.reject("Must provide URL")
    }
    guard let key = call.getString("key") else {
      return call.reject("Must provide key")
    }
    guard let url = URL(string: urlString) else {
      return call.reject("Invalid URL")
    }
    
    let jar = HTTPCookieStorage.shared
    
    let cookie = jar.cookies(for: url)?.first(where: { (cookie) -> Bool in
      return cookie.name == key
    })
    if cookie != nil {
      jar.deleteCookie(cookie!)
    }
    
    call.resolve()
  }
  
  @objc public func clearCookies(_ call: CAPPluginCall) {
    guard let urlString = call.getString("url") else {
      return call.reject("Must provide URL")
    }
    guard let url = URL(string: urlString) else {
      return call.reject("Invalid URL")
    }
    let jar = HTTPCookieStorage.shared
    jar.cookies(for: url)?.forEach({ (cookie) in
      jar.deleteCookie(cookie)
    })
    call.resolve()
  }

  
  /* PRIVATE */
  
  // Handle GET operations
  func get(_ call: CAPPluginCall, _ url: inout URL, _ method: String, _ headers: [String:String], _ params: [String:String]) {
    setUrlQuery(&url, params)
    
    var request = URLRequest(url: url)
    
    request.httpMethod = method
    
    setRequestHeaders(&request, headers,"")

    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
      if error != nil {
        call.reject("Error", "GET", error, [:])
        return
      }
      
      let res = response as! HTTPURLResponse
     
      call.resolve(self.buildResponse(data, res))
    }
    
    task.resume()
  }
  
  func setUrlQuery(_ url: inout URL, _ params: [String:String]) {
    var cmps = URLComponents(url: url, resolvingAgainstBaseURL: true)
    if cmps?.queryItems == nil {
      cmps?.queryItems = []
    }
    cmps!.queryItems?.append(contentsOf: params.map({ (key, value) -> URLQueryItem in
      return URLQueryItem(name: key, value: value)
    }))
    url = cmps!.url!
  }
  
  func setRequestHeaders(_ request: inout URLRequest, _ headers: [String:String], _ boundary: String) {
    headers.keys.forEach { (key) in
        let value: String
        if key.lowercased().contains("multipart/form-data") {
         value = headers[key]! + "; WebKitFormBoundary=----" + boundary
        }else{
            value = headers[key]!
        }
        
     
      request.addValue(value, forHTTPHeaderField: key)
    }
  }
  
  // Handle mutation operations: DELETE, PATCH, POST, and PUT
  func mutate(_ call: CAPPluginCall, _ url: URL, _ method: String, _ headers: [String:String]) {
    let dataObject = call.getObject("data")
    let dataArray  = call.getArray("dataForm",dataForm.self);

    
    var request = URLRequest(url: url)
    request.httpMethod = method
    
    let boundary = "Boundary-" + randomString(length: 16)

    
    setRequestHeaders(&request, headers, boundary)
    
    let contentType = getRequestHeader(headers, "Content-Type") as? String
    
    if (dataObject != nil || dataArray != nil )  && contentType != nil {
      do {
        
        if contentType!.contains("multipart/form-data"){
            
            var dataMultiPart = Data()
            let lineBreak = "\r\n"
        
            dataObject?.keys.forEach { (key) in
                let fileArray:[Any] = dataObject?[key] as! [Any]
                fileArray.forEach { (fileKey) in
                    let temp = fileKey as? Dictionary<String, Any>
                    let type  = temp?["type"] as! String
                    let value  = temp?["value"] as! String
                    let name  = temp?["name"] as! String
                    
                

                    if(type.contains("description") == true){
                        
                        dataMultiPart.append("--\(boundary + lineBreak)")
                        dataMultiPart.append("Content-Disposition: form-data; name=\"description\"\(lineBreak + lineBreak)")
                        dataMultiPart.append("\(value + lineBreak)")
                   
                    
                    }else{
                        let mimeType  = temp?["mimeType"] as! String
                    
                        
                        let imageData = Data (base64Encoded: value)
                        
                       // let mimeType = FilesystemUtils.mimeTypeForPath(path: name)

                        dataMultiPart.append("--\(boundary + lineBreak)")
                        dataMultiPart.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(name)\"\(lineBreak)")
                        dataMultiPart.append("Content-Type: \(mimeType + lineBreak + lineBreak)")
                      //  dataMultiPart.append(imageData! )
                        dataMultiPart.append(lineBreak)
                    }
                }
            }
            dataMultiPart.append("--\(boundary)--\(lineBreak)")
            
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let tempMultiPart = String(String(decoding: dataMultiPart, as: UTF8.self))
            let tempCount = dataMultiPart.count
            request.setValue(String(tempCount), forHTTPHeaderField: "content-length")
            request.httpBody = dataMultiPart
            
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                print(response);
              if error != nil {
                CAPLog.print("Error on upload file", data, response, error)
                call.reject("Error", "UPLOAD", error, [:])
                return
              }
                
                
                let res = response as! HTTPURLResponse
               
                call.resolve(self.buildResponse(data, res))
            }
            
            task.resume()
            
            return;
        
        }else{
            request.httpBody = try getRequestData(request, dataObject!, contentType!,boundary)
        }
        
        
      } catch let e {
        call.reject("Unable to set request data", "MUTATE", e)
        return
      }
    }

    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
      if error != nil {
        call.reject("Error", "MUTATE", error, [:])
        return
      }
      
      let res = response as! HTTPURLResponse
     
      call.resolve(self.buildResponse(data, res))
    }
    
    task.resume()
  }

  func buildResponse(_ data: Data?, _ response: HTTPURLResponse) -> [String:Any] {
    
    var ret = [:] as [String:Any]
    
    ret["status"] = response.statusCode
    ret["headers"] = response.allHeaderFields
    
    let contentType = response.allHeaderFields["Content-Type"] as? String

    if data != nil && contentType != nil && contentType!.contains("application/json") {
      if let json = try? JSONSerialization.jsonObject(with: data!, options: .mutableContainers) {
        ret["data"] = json
      }
    } else {
      if (data != nil) {
        ret["data"] = String(data: data!, encoding: .utf8);
      } else {
        ret["data"] = ""
      }
    }
    
    return ret
  }
  
  func getRequestHeader(_ headers: [String:Any], _ header: String) -> Any? {
    var normalizedHeaders = [:] as [String:Any]
    headers.keys.forEach { (key) in
      normalizedHeaders[key.lowercased()] = headers[key]
    }
    return normalizedHeaders[header.lowercased()]
  }
  
    func getRequestData(_ request: URLRequest, _ data: [String:Any], _ contentType: String, _ boundary: String) throws -> Data? {
    if contentType.contains("application/json") {
      return try setRequestDataJson(request, data)
    } else if contentType.contains("application/x-www-form-urlencoded") {
        return setRequestDataFormUrlEncoded(request, data)
    }
    return nil
  }
  
  func setRequestDataJson(_ request: URLRequest, _ data: [String:Any]) throws -> Data? {
    let jsonData = try JSONSerialization.data(withJSONObject: data)
    return jsonData
  }
  
  func setRequestDataFormUrlEncoded(_ request: URLRequest, _ data: [String:Any]) -> Data? {
    guard var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else {
      return nil
    }
    components.queryItems = []
    data.keys.forEach { (key) in
      components.queryItems?.append(URLQueryItem(name: key, value: "\(data[key] ?? "")"))
    }
    
    if components.query != nil {
      return Data(components.query!.utf8)
    }
    
    return nil
  }
  
    func setRequestDataMultipartFormData(_ request: URLRequest, _ data: Dictionary<String, Any> , _ boundary: String) -> Data? {
        
        
        if let users = data as? [[String : Any]] {
            for user in users {
                print(user["id"])
            }
        }
        
        

     var dataMultiPart = Data()
        dataMultiPart.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)

        /*
        for temp  in data  {
            
            
            guard let addresses = temp["value"] as? [[String: Any]] else {
         
                return nil
            }
            
            
            let file = temp["value"]
        let mimeType = FilesystemUtils.mimeTypeForPath(path: file.name)
            
        if(file.type.contains("description") == true){
            let myData:String = file.value
            dataMultiPart.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            dataMultiPart.append("Content-Disposition: form-data; name=\"\(file.name)\"\r\n".data(using: .utf8)!)
            dataMultiPart.append(myData.data(using: .utf8)!)
            dataMultiPart.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        }else{
            let myData:String = file.value
            dataMultiPart.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            dataMultiPart.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.name)\"\r\n".data(using: .utf8)!)
            dataMultiPart.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            dataMultiPart.append(file.value.data(using: .utf8)!)
            dataMultiPart.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        }
    }*/

    return dataMultiPart
  }
  
  
  func generateFullMultipartRequestBody(_ url: URL, _ name: String, _ boundary: String) throws -> Data {
    var data = Data()
    
    let fileData = try Data(contentsOf: url)

    
    let fname = url.lastPathComponent
    let mimeType = FilesystemUtils.mimeTypeForPath(path: fname)
    data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
    data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fname)\"\r\n".data(using: .utf8)!)
    data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    data.append(fileData)
    data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    
    return data
  }
    
    func randomString(length: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
 
}
extension Data {
   mutating func append(_ string: String) {
        if let data = string.data(using: .utf8){
            append(data)
        }
    }
}

extension Data {

    init?(base64String: String) {
        self.init(base64Encoded: base64String)
    }

    var base64String: String {
        return self.base64EncodedString()
    }

}

extension String {

    init?(base64String: String) {
        guard let data = Data(base64String: base64String) else {
            return nil
        }
        self.init(data: data, encoding: .utf8)
    }

    var base64String: String {
        return self.data(using: .utf8)!.base64String
    }

}
