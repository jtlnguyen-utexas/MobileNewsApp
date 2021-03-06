//
//  PDFComposer.swift
//  MobileNewsApp
//
//  Created by Nelia Perez on 3/25/17.
//  Copyright © 2017 cs378. All rights reserved.
//

import UIKit
import AWSCore
import AWSS3

class PDFComposer: NSObject {

    let pathToCompleteStoryHTMLTemplate = Bundle.main.path(forResource: "complete_story", ofType: "html")
    let pathToSingleEntryHTMLTemplate = Bundle.main.path(forResource: "single_entry", ofType: "html")
    
    var story: Story?
    
    var pdfFilename: String!
    
    //let pathToSingleItemHTMLTemplate = Bundle.main.path(forResource: "single_item", ofType: "html")
    
    init(story: Story) {
        self.story = story
    }
    
    func renderHTML() -> String! {
        do {
            var HTMLContent = try String(contentsOfFile: pathToCompleteStoryHTMLTemplate!)
            
            HTMLContent = HTMLContent.replacingOccurrences(of: "#TITLE#", with: story!.title!)
            HTMLContent = HTMLContent.replacingOccurrences(of: "#AUTHOR#", with: story!.author!)
                        HTMLContent = HTMLContent.replacingOccurrences(of: "#GENRE#", with: story!.genre!)
            HTMLContent = HTMLContent.replacingOccurrences(of: "#TIME#", with: "\(story!.timeLimit!)")
            HTMLContent = HTMLContent.replacingOccurrences(of: "#NUMPARTICIPANTS#", with: "\(story!.participants)")
            HTMLContent = HTMLContent.replacingOccurrences(of: "#NUMTURNS#", with: "\(story!.totalTurns!)")
            HTMLContent = HTMLContent.replacingOccurrences(of: "#PROMPT#", with: story!.prompt!)
            
            var allEntries = ""
            
            for entry in (story?.entries)! {
                var itemHTMLContent: String!
                
                itemHTMLContent = try String(contentsOfFile: self.pathToSingleEntryHTMLTemplate!)
                
                itemHTMLContent = itemHTMLContent.replacingOccurrences(of: "#ENTRY#", with: entry.text!)
                
                 allEntries += itemHTMLContent
            }
            
            HTMLContent = HTMLContent.replacingOccurrences(of: "#ENTRIES#", with: allEntries)
            
            return HTMLContent
        }
        
        catch {
            print("Unable to open and use HTML template files.")
        }
        
        return nil
    }
    
    func exportHTMLContentToPDF(HTMLContent: String) -> NSURL {
        let printPageRenderer = CustomPrintPageRenderer()
        let printFormatter = UIMarkupTextPrintFormatter(markupText: HTMLContent)
        printPageRenderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
        
        let pdfData = drawPDFUsingPrintPageRenderer(printPageRenderer: printPageRenderer)
        
        let fileManager = FileManager.default
        let path = (NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString).appendingPathComponent("\(story!.id!).pdf")
        fileManager.createFile(atPath: path as String, contents: pdfData as Data?, attributes: nil)
        
        let fileUrl = NSURL(fileURLWithPath: path)
        
        pdfData?.write(toFile: "\(fileUrl)", atomically: true)
        
        return fileUrl
    }
    
    func drawPDFUsingPrintPageRenderer(printPageRenderer: UIPrintPageRenderer) -> NSData! {
        let data = NSMutableData()
        
        UIGraphicsBeginPDFContextToData(data, CGRect.zero, nil)
        printPageRenderer.prepare(forDrawingPages: NSMakeRange(0, printPageRenderer.numberOfPages))
        
        let bounds = UIGraphicsGetPDFContextBounds()
        
        for i in 0...(printPageRenderer.numberOfPages - 1) {
            UIGraphicsBeginPDFPage()
            printPageRenderer.drawPage(at: i, in: bounds)
        }
        
        UIGraphicsEndPDFContext();
        return data
    }

    func uploadToS3(url: NSURL) {
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType:.USWest2,
                                                                identityPoolId:"us-west-2:bb5dab7f-bb7e-405b-8498-6a5fb644f4aa")
        
        let configuration = AWSServiceConfiguration(region:.USWest2, credentialsProvider:credentialsProvider)
        
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        //file information
        let S3BucketName = "mobile-news-app"
        
        let uploadRequest = AWSS3TransferManagerUploadRequest()
        uploadRequest?.bucket = S3BucketName
        uploadRequest?.key = "\(story!.id!).pdf"
        uploadRequest?.body = url as URL!
        uploadRequest?.contentType = "application/pdf"
        
        let transferManager = AWSS3TransferManager.default()
       
        transferManager.upload(uploadRequest!).continueWith(executor: AWSExecutor.mainThread(), block: { (task:AWSTask<AnyObject>) -> Any? in
            
            if let error = task.error as? NSError {
                if error.domain == AWSS3TransferManagerErrorDomain, let code = AWSS3TransferManagerErrorType(rawValue: error.code) {
                    switch code {
                    case .cancelled, .paused:
                        break
                    default:
                        print("Error uploading: \(uploadRequest?.key) Error: \(error)")
                    }
                } else {
                    print("Error uploading: \(uploadRequest?.key) Error: \(error)")
                }
                return nil
            }
            
            let uploadOutput = task.result
            print("Upload complete for: \(uploadRequest?.key)")
            return nil
        })
    }
}
