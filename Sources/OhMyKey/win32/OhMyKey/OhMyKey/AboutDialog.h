/*----------------------------------------------------------
OhMyKey - The Cross platform Open source Vietnamese Keyboard application.

Copyright (C) 2019 Mai Vu Tuyen (original OpenKey)
Copyright (C) 2026 Hung Doan (OhMyKey fork)
Github: https://github.com/hungdoansy/OhMyKey
Based on OpenKey: https://github.com/tuyenvm/OpenKey

This file is belong to the OhMyKey project, Win32 version
which is released under GPL license.
You can fork, modify, improve this program. If you
redistribute your new version, it MUST be open source.
-----------------------------------------------------------*/
#pragma once
#include "BaseDialog.h"

class AboutDialog :	public BaseDialog {
protected:
	INT_PTR eventProc(HWND hDlg, UINT uMsg, WPARAM wParam, LPARAM lParam);
	void initDialog();
public:
	AboutDialog(const HINSTANCE & hInstance, const int & resourceId);
	~AboutDialog();
	virtual void fillData() override;
private:
	HWND hUpdateButton;
	void onUpdateButton();
};