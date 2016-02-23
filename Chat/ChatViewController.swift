//
//  ChatViewController.swift
//  Chat
//
//  Created by Alexander Danilyak on 23/02/16.
//  Copyright © 2016 Alexander Danilyak. All rights reserved.
//

import UIKit
import PubNub

class ChatViewController: UIViewController, PNObjectEventListener, UITableViewDelegate, UITextFieldDelegate, UITableViewDataSource {

    @IBOutlet weak var tableview: UITableView!
    
    var alertController: UIAlertController?
    var alertAction: UIAlertAction?
    var arrayOfColors: Array<UIColor>?
    
    // Мое имя в чате
    var name: String?
    var colorIndex: Int?
    
    // Имя канала
    let channelName = "testChannel"
    
    // Клиент для работы с PubNub
    var client: PubNub?
    
    // Будем тут хранить историю сообщений
    var messages: Array<[String: AnyObject]>?
    
    // Поле ввода сообщения
    @IBOutlet weak var messageTextField: UITextField!
    // Кнопка отправить
    @IBOutlet weak var sendButton: UIBarButtonItem!
    // Тулбар который содержит поле отправки и кнопку
    @IBOutlet weak var toolbar: UIToolbar!
    // Констрайнт тулбара к нижней границе
    @IBOutlet weak var toolbarToBottom: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Настраиваем таблицу
        tableview.delegate = self
        
        // Чтобы строчки растягивались под контент
        tableview.estimatedRowHeight = 44.0
        tableview.rowHeight = UITableViewAutomaticDimension
        
        // Небольшая фигня, чтобы выбирать цвет ника рандомно (просто симпатичней, листай дальше)
        self.arrayOfColors = [UIColor.redColor(), UIColor.greenColor(), UIColor.blueColor(), UIColor.yellowColor(), UIColor.grayColor(), UIColor.cyanColor(), UIColor.magentaColor()]
        self.colorIndex = Int(arc4random_uniform(UInt32(self.arrayOfColors!.count)))
        
        // Инициализируем хранилище для сообщений
        self.messages = Array()
        
        // Инициализируем и настраиваем контроллер, который спрашивает Имя
        self.setUpAlertController()
        
        // Настраиваем нижний бар с полем ввода сообщения
        self.setUpSendToolbar()
        
        // Подписываемся на уведомления клавиатуры, чтобы знать когда она появилась и когда исчезла
        self.registerForKeyboardNotifications()
    }
    
    // проверяем количество символов в имене, если 0 не пускаем дальше
    func shouldEnableAlertControllerOkButton(alertController: UIAlertController) -> Bool {
        return !((alertController.textFields![0] as UITextField).text?.isEmpty)!
    }
    
    func setUpAlertController() {
        self.alertController = UIAlertController(title: "Enter your name", message: "Please, enter your name for chat room", preferredStyle: .Alert)
        
        var nameTextField: UITextField?
        self.alertController!.addTextFieldWithConfigurationHandler { (textField) -> Void in
            nameTextField = textField
            nameTextField!.addTarget(self, action: Selector("nameDidChange"), forControlEvents: .EditingChanged)
            nameTextField?.placeholder = "Name"
        }
        
        self.alertAction = UIAlertAction(title: "Ok", style: .Default) { (action) -> Void in
            if (nameTextField?.text ?? "").isEmpty {
                
            } else {
                self.name = nameTextField?.text
                print("Ok, connecting to chat room...")
                self.configPubNubAndConnectToChannelWithName(self.channelName)
            }
            self.messageTextField.becomeFirstResponder()
        }
        
        self.alertAction?.enabled = false
        
        self.alertController!.addAction(self.alertAction!)
    }
    
    // Проверяем изменилось ли имя, чтобы понимать когда активировать кнопку ОК
    func nameDidChange() {
        self.alertAction!.enabled = self.shouldEnableAlertControllerOkButton(self.alertController!)
    }
    
    func setUpSendToolbar() {
        self.messageTextField.delegate = self
        self.messageTextField.frame = CGRectMake(0, 0, self.view.frame.width - 16 - 2*self.sendButton.width, self.messageTextField.frame.height);
    }
    
    func registerForKeyboardNotifications() {
        let center = NSNotificationCenter.defaultCenter()
        center.addObserver(self, selector: Selector("keyboardWillShow:"), name: UIKeyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: Selector("keyboardWillHide:"), name: UIKeyboardWillHideNotification, object: nil)
    }
    
    override func viewDidAppear(animated: Bool) {
        // Показываем контроллер, который спрашвает про имя
        presentViewController(self.alertController!, animated: true, completion: nil)
    }
    
    func keyboardWillShow(notification: NSNotification) {
        print("Keyboard did show")
        let keyboardSize = (notification.userInfo![UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.CGRectValue()
        let duration = notification.userInfo![UIKeyboardAnimationDurationUserInfoKey] as? NSNumber
        // Анимируем всплытие нижнего тулбара с такой же продолжительностью, как и у высплытия клавиатуры
        // Тут возможен небольшой лаг в интерфейсе из-за того, что нотификейшн клавиатуры идет до этого места коде не всегда одно и то же время (Чтот сложно, читай те манул по NSNotificationCenter)
        UIView.animateWithDuration(NSTimeInterval.init(duration!)) { () -> Void in
            self.toolbarToBottom.constant = keyboardSize!.height
        }
        
        // Если есть сообщения то хотит проскролить в самый них и видеть последнее
        if (self.messages!.count != 0) {
            self.tableview.scrollToRowAtIndexPath(NSIndexPath(forRow: self.messages!.count, inSection: 0), atScrollPosition: .Bottom, animated: true)
        }
    }
    
    func keyboardWillHide(notification: NSNotification) {
        print("Keyboard did hide")
        let duration = notification.userInfo![UIKeyboardAnimationDurationUserInfoKey] as? NSNumber
        UIView.animateWithDuration(NSTimeInterval.init(duration!)) { () -> Void in
            self.toolbarToBottom.constant = 0
        }
    }
    
    // Количество строк в таблице в секции, у нас секция одна, поэтому игнорируем номер секции
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.messages!.count
    }
    
    // Генерим ячейки таблицы и заполняем данными из хранилища
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableview.dequeueReusableCellWithIdentifier("chatCell")
        (cell!.viewWithTag(100) as! UILabel).text = (self.messages![indexPath.row]["name"] as! String)
        let colorIndex = (self.messages![indexPath.row]["color"] as! Int)
        (cell!.viewWithTag(100) as! UILabel).textColor = self.arrayOfColors![colorIndex]
        (cell!.viewWithTag(101) as! UILabel).text = (self.messages![indexPath.row]["message"] as! String)
        return cell!
    }
    
    
    // Настраиваем PubNub и привязываемся к каналу
    func configPubNubAndConnectToChannelWithName(channelName: String!) {
        
        // Ключи от моего аккауна, вам надо будет изменить
        let config = PNConfiguration(publishKey: "pub-c-a02b459e-4c8f-4ba6-a33f-1914246a2410", subscribeKey: "sub-c-93a6a040-d9a6-11e5-8758-02ee2ddab7fe")
        self.client = PubNub.clientWithConfiguration(config)
        
        // Говорим, что будем обрабатывать сообщения о получении новых данных тут же (то есть в self)
        self.client?.addListener(self)
        
        // Подписываемся на канал, ставим лайки *шутка*
        self.client?.subscribeToChannels([channelName], withPresence: false)
    }
    
    // Обработчик полученных сообщений
    func client(client: PubNub!, didReceiveMessage message: PNMessageResult!) {
        let recivedMessage = message.data.message as! [String: AnyObject]
        self.messages?.append(recivedMessage)
        
        self.tableview.insertRowsAtIndexPaths([NSIndexPath(forRow: self.messages!.count - 1, inSection: 0)], withRowAnimation: .Bottom)
        self.tableview.scrollToRowAtIndexPath(NSIndexPath(forRow: self.messages!.count - 1, inSection: 0), atScrollPosition: .Bottom, animated: true)
    }

    // Кнопка отправить сообщения
    @IBAction func sendPushed(sender: AnyObject) {
        print("Send pushed")
        let messageInfo = ["name": self.name!, "message": self.messageTextField.text!, "color": self.colorIndex!]
        self.client?.publish(messageInfo, toChannel: self.channelName, compressed: false, withCompletion: nil)
        self.messageTextField.text = ""
    }
    
}
