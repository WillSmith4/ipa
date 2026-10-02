//
//  LocalizationHelper.swift
//  VoidLink
//
//  Created by True砖家 on 2024/7/23.
//  Copyright © True砖家 on Bilibili. All rights reserved.
//

extension LocalizationHelper {
    static func localizedString(forKey key: String, _ args: CVarArg...) -> String {
        let format = localizedTemplate(forKey: key)
        guard !args.isEmpty else { return format }
        return String(format: format, arguments: args)
    }
}
